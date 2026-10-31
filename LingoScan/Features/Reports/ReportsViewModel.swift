import Foundation
import LingoCore
import Observation

/// Estado de Reportes: período elegido (7/14/30/90 días), reporte calculado y caché por período.
///
/// `ReportBuilder.build` corre siempre en `Task.detached` (en Debug, 90 días tardan segundos). Se recalcula al
/// aparecer, al volver a primer plano, al cambiar de período o de rango de referencia, y como mucho una vez por
/// minuto para el mismo período: dentro de ese minuto se reutiliza la caché. Mientras se recalcula se sigue
/// mostrando el último reporte (`isLoading`; `isShowingStaleContent` si es de otro período).
@MainActor
@Observable
final class ReportsViewModel {
    enum LoadFailure: Error, Equatable {
        case unavailable
    }

    /// Clave de `UserDefaults` con el último período elegido.
    static let presetKey = "reports.preset"
    static let defaultPreset = ReportPeriod.Preset.days14
    /// Intervalo mínimo entre dos cálculos del mismo período con la misma configuración.
    static let refreshInterval: TimeInterval = 60

    private(set) var preset: ReportPeriod.Preset
    private(set) var content: ReportContent?
    private(set) var failure: LoadFailure?
    /// Rango de referencia del usuario (el de Hoy) y ventana de noche por defecto.
    private(set) var configuration: ReportConfiguration

    @ObservationIgnored private let dataSource: any ReportsDataSource
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cache: [ReportPeriod.Preset: CacheEntry] = [:]
    /// Cálculos en curso. Un resultado solo se publica si sigue siendo el del período y rango elegidos.
    private var loading: Set<LoadKey> = []
    @ObservationIgnored private var hasAppeared = false

    private struct LoadKey: Hashable {
        let preset: ReportPeriod.Preset
        let configuration: ReportConfiguration
    }

    private struct CacheEntry {
        let content: ReportContent
        let builtAt: Date
        let configuration: ReportConfiguration
    }

    init(
        dataSource: any ReportsDataSource,
        clock: @escaping @Sendable () -> Date = { .now },
        timeZone: TimeZone = .current,
        defaults: UserDefaults = .standard
    ) {
        self.dataSource = dataSource
        self.clock = clock
        self.timeZone = timeZone
        self.defaults = defaults
        preset = ReportPeriod.Preset(rawValue: defaults.integer(forKey: Self.presetKey)) ?? Self.defaultPreset
        configuration = Self.configuration(defaults: defaults)
    }

    /// Fuente real (`SQLiteStore`).
    static func live(store: SQLiteStore) -> ReportsViewModel {
        ReportsViewModel(dataSource: LiveReportsDataSource(store: store))
    }

    /// Datos sintéticos rotulados (previsualización y `-previewSensorState`): 14 días.
    static func preview(data: PreviewData = PreviewData()) -> ReportsViewModel {
        ReportsViewModel(dataSource: PreviewReportsDataSource(data: data))
    }

    var isSynthetic: Bool { dataSource.isSynthetic }

    /// Se está calculando el período y rango elegidos.
    var isLoading: Bool { loading.contains(currentKey) }

    private var currentKey: LoadKey { LoadKey(preset: preset, configuration: configuration) }

    /// `true` si lo que se ve es de otro período (se está calculando el elegido).
    var isShowingStaleContent: Bool { content.map { $0.preset != preset } ?? false }

    // MARK: Acciones

    func appear() async {
        hasAppeared = true
        await load()
    }

    /// Vuelta a primer plano: recalcula si pasó el intervalo mínimo.
    func sceneDidBecomeActive() async {
        guard hasAppeared else { return }
        await load()
    }

    func select(_ newPreset: ReportPeriod.Preset) async {
        guard newPreset != preset else { return }
        preset = newPreset
        defaults.set(newPreset.rawValue, forKey: Self.presetKey)
        await load()
    }

    /// Rango de referencia de Ajustes (`ReferenceLines`); recalcula si cambió.
    func updateReference(low: Int, high: Int) async {
        let normalized = ReferenceLines.normalized(low: low, high: high)
        let updated = ReportConfiguration(range: normalized.low...normalized.high)
        guard updated != configuration else { return }
        configuration = updated
        guard hasAppeared else { return }
        await load()
    }

    /// Reintento manual tras un fallo: ignora la caché.
    func retry() async {
        await load(force: true)
    }

    // MARK: Cálculo

    func load(force: Bool = false) async {
        let key = currentKey
        let preset = key.preset
        let configuration = key.configuration
        let now = clock()
        let cached = cache[preset].flatMap { $0.configuration == configuration ? $0 : nil }
        if let cached, !force, now.timeIntervalSince(cached.builtAt) < Self.refreshInterval {
            content = cached.content
            failure = nil
            return
        }
        if let cached { content = cached.content }
        guard !loading.contains(key) else { return }

        loading.insert(key)
        let source = dataSource
        let timeZone = timeZone
        let result = await Task.detached(priority: .userInitiated) { () -> Result<ReportContent, any Error> in
            do {
                let period = ReportPeriod.preset(preset, endingAt: UTCInstant(now), timeZone: timeZone)
                async let readings = source.readings(in: period.dataRange)
                async let events = source.events(in: period.dataRange)
                let bundle = ReportBuilder.build(
                    readings: try await readings, events: try await events, period: period, configuration: configuration)
                return .success(ReportContent(preset: preset, bundle: bundle))
            } catch {
                return .failure(error)
            }
        }.value

        loading.remove(key)
        let isCurrent = key == currentKey
        switch result {
        case .success(let built):
            cache[preset] = CacheEntry(content: built, builtAt: now, configuration: configuration)
            if isCurrent {
                content = built
                failure = nil
            }
        case .failure:
            if isCurrent { failure = .unavailable }
        }
    }

    /// Rango de referencia guardado por Ajustes (las mismas claves que Hoy).
    static func configuration(defaults: UserDefaults) -> ReportConfiguration {
        let low = defaults.object(forKey: ReferenceLines.lowKey) as? Int ?? ReferenceLines.defaultLow
        let high = defaults.object(forKey: ReferenceLines.highKey) as? Int ?? ReferenceLines.defaultHigh
        let normalized = ReferenceLines.normalized(low: low, high: high)
        return ReportConfiguration(range: normalized.low...normalized.high)
    }
}
