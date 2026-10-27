import Foundation
import LingoCore
import Observation

/// Estado de Hoy: último valor elegible, curva del período, huecos, marcas y estado del sensor.
/// Sin lógica de protocolo; todo llega por `TodayDataSource` y `SensorStatusSource`.
@MainActor
@Observable
final class TodayViewModel {
    enum LoadFailure: Error, Equatable {
        case readingsUnavailable
    }

    /// Período de la curva. Al cambiarlo, la vista vuelve a llamar a `refresh()` con `.task(id:)`.
    var period: TodayPeriod = .sixHours

    private(set) var latest: GlucoseReading?
    private(set) var segments: [GlucoseSegment] = []
    private(set) var gaps: [GlucoseGap] = []
    private(set) var marks: [DiaryMark] = []
    private(set) var sensor: SensorStatusSnapshot = .noSensor
    private(set) var failure: LoadFailure?
    /// `true` tras la primera carga, para no mostrar el estado vacío antes de tiempo.
    private(set) var hasLoaded = false
    /// Instante con el que se calculó la ventana visible.
    private(set) var windowEnd: Date

    private let dataSource: any TodayDataSource
    private let sensorSource: any SensorStatusSource
    private let clock: @Sendable () -> Date

    /// Sin lectura en más de 5 minutos el dato se considera atrasado (`ARQUITECTURA.md` §3).
    static let staleAfter: TimeInterval = 300

    init(
        dataSource: any TodayDataSource,
        sensorSource: any SensorStatusSource,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.dataSource = dataSource
        self.sensorSource = sensorSource
        self.clock = clock
        self.windowEnd = clock()
    }

    // MARK: Derivados

    var windowStart: Date { windowEnd.addingTimeInterval(-period.duration) }

    var points: [GlucosePoint] { segments.flatMap(\.points) }

    var latestValue: Int? { latest?.value }

    var trend: TrendDirection? { TrendDirection(rawTrend: latest?.raw.trend) }

    var isSynthetic: Bool { latest?.synthetic ?? sensor.profile?.synthetic ?? false }

    /// Minutos enteros desde la última lectura elegible; `nil` si no hay lectura.
    func ageMinutes(at now: Date) -> Int? {
        guard let latest else { return nil }
        return max(0, Int(now.timeIntervalSince(latest.measuredAt.date) / 60))
    }

    func isStale(at now: Date) -> Bool {
        guard let latest else { return false }
        return now.timeIntervalSince(latest.measuredAt.date) > Self.staleAfter
    }

    /// Valor, tendencia, antigüedad y estado del sensor en una sola frase para VoiceOver.
    func spokenSummary(at now: Date) -> String {
        guard let value = latestValue, let minutes = ageMinutes(at: now) else {
            return String(localized: "today.a11y.noValue", defaultValue: "Sin lectura válida todavía")
        }
        let age = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        let trendText = trend?.title ?? TrendDirection.unknownTitle
        return String(
            localized: "today.a11y.value",
            defaultValue: "\(value) miligramos por decilitro, \(trendText), hace \(age), \(sensor.state.spokenPhrase)"
        )
    }

    /// Rango vertical de la curva: incluye siempre la banda de referencia con algo de margen.
    var chartValueDomain: ClosedRange<Int> {
        let values = points.map(\.value)
        let low = min(values.min() ?? Tokens.ReferenceRange.lower, 54)
        let high = max(values.max() ?? Tokens.ReferenceRange.upper, 220)
        return ((low - 10) / 10 * 10)...((high + 10 + 9) / 10 * 10)
    }

    /// Punto más cercano a una fecha, para la lectura al tocar la curva.
    func nearestPoint(to date: Date) -> GlucosePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: Carga

    /// Carga el estado del sensor y sigue los avisos de datos nuevos y los cambios de estado hasta que se cancela la tarea.
    /// La primera carga de la curva la dispara la vista con `.task(id: period)`.
    func observe() async {
        await refreshSensor()
        async let changes: Void = followChanges()
        async let statuses: Void = followSensor()
        _ = await (changes, statuses)
    }

    private func followChanges() async {
        for await _ in dataSource.changes() {
            await refresh()
        }
    }

    private func followSensor() async {
        for await snapshot in sensorSource.statusUpdates() {
            sensor = snapshot
        }
    }

    func refreshSensor() async {
        sensor = await sensorSource.currentStatus()
    }

    /// Recalcula la ventana del período y la última lectura.
    func refresh() async {
        let end = clock()
        windowEnd = end
        defer { hasLoaded = true }
        let range = UTCInstant(end.addingTimeInterval(-period.duration))...UTCInstant(end)
        do {
            async let latestReading = dataSource.latestEligibleReading()
            async let readings = dataSource.readings(in: range)
            async let events = dataSource.diaryEvents(in: range)
            let (newLatest, newReadings, newEvents) = try await (latestReading, readings, events)
            latest = newLatest
            let newSegments = GlucoseSegmenter.segments(from: newReadings.compactMap(GlucosePoint.init))
            segments = newSegments
            gaps = GlucoseSegmenter.gaps(in: newSegments)
            marks = newEvents.compactMap(DiaryMark.init).sorted { $0.date < $1.date }
            failure = nil
        } catch {
            failure = .readingsUnavailable
        }
    }
}
