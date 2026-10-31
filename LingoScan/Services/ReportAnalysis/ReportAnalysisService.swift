import Foundation
import LingoCore
import Observation

/// Análisis de un reporte con IA (T-27d, D-30). **Una petición por toque, sin reintentos**, con el proveedor, la clave y
/// el modelo del asistente de comidas (D-19). Cada intento queda en `report_analyses` como `succeeded`, `rejected`
/// (el validador descartó la respuesta entera) o `failed`, con el SHA-256 del mensaje enviado. La clave solo se lee
/// del Llavero en el instante de enviar y nunca se guarda en el estado observable.
@MainActor @Observable
final class ReportAnalysisService {
    private(set) var state: ReportAnalysisState = .idle
    /// Análisis anteriores del mismo tramo (mismo número de días), del más reciente al más antiguo.
    private(set) var history: [ReportAnalysisRecord] = []
    /// Modelo elegido; `nil` si falta proveedor, clave o modelo.
    private(set) var model: LLMModel?
    /// "Proveedor · modelo" para mostrar.
    private(set) var modelLabel: String?
    private(set) var outgoing: ReportAnalysisPreview?
    /// Registro del historial que se está mostrando (`nil` si es el análisis recién hecho).
    private(set) var shownRecordID: String?

    var isConfigured: Bool { model != nil }

    @ObservationIgnored private let keys: LLMKeyStore
    @ObservationIgnored private let settings: LLMSettingsStore
    @ObservationIgnored private let store: any ReportAnalysisStoring
    @ObservationIgnored private let client: ReportAnalysisClient
    @ObservationIgnored private let locale: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeID: @Sendable () -> String
    @ObservationIgnored private var preparedPeriod: ReportPeriod?

    static let historyFetchLimit = 200

    init(keys: LLMKeyStore, settings: LLMSettingsStore, store: any ReportAnalysisStoring,
         client: ReportAnalysisClient = ReportAnalysisClient(), locale: String = Locale.current.identifier,
         now: @escaping @Sendable () -> Date = { Date() },
         makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.keys = keys
        self.settings = settings
        self.store = store
        self.client = client
        self.locale = locale
        self.now = now
        self.makeID = makeID
    }

    /// App real: claves y ajustes del asistente de comidas, red real, análisis en SQLite.
    static func live(store: SQLiteStore, assistant: MealAssistantServices) -> ReportAnalysisService {
        ReportAnalysisService(keys: assistant.keys, settings: assistant.settings, store: store)
    }

    /// Sin asistente configurado ni almacén real: previsualizaciones.
    static var preview: ReportAnalysisService {
        ReportAnalysisService(
            keys: LLMKeyStore(itemFor: { _ in PreviewSecretItem() }),
            settings: LLMSettingsStore(defaults: UserDefaults(suiteName: "report-analysis-preview") ?? .standard),
            store: PreviewReportAnalysisStore())
    }

    // MARK: - Preparar la hoja

    /// Al abrir la hoja de un reporte: reinicia el estado si cambió de período, relee la configuración, calcula lo que
    /// se enviará y carga el historial. No envía nada.
    func prepare(for bundle: ReportBundle) async {
        if preparedPeriod != bundle.period {
            if state != .loading { state = .idle }
            shownRecordID = nil
            outgoing = nil
        }
        preparedPeriod = bundle.period
        await refreshConfiguration()
        await refreshHistory(for: bundle.period)
        guard let model else {
            outgoing = nil
            return
        }
        let locale = locale
        let request = try? await Task.detached(priority: .userInitiated) {
            try ReportAnalysisRequest(bundle: bundle, locale: locale)
        }.value
        outgoing = request.map { ReportAnalysisPreview(request: $0, model: model) }
    }

    /// Relee proveedor, modelo y clave (la clave solo para saber si existe).
    func refreshConfiguration() async {
        if let configuration = await resolveConfiguration() {
            model = configuration.model
            modelLabel = configuration.label
        } else {
            model = nil
            modelLabel = nil
        }
    }

    // MARK: - Analizar

    /// Envía **una** petición con el reporte. Sigue aunque se cierre la hoja (ya se pagó) y deja el resultado en el
    /// historial. Devuelve la tarea para poder esperarla (pruebas).
    @discardableResult
    func analyze(_ bundle: ReportBundle) -> Task<Void, Never> {
        Task { await run(bundle) }
    }

    func run(_ bundle: ReportBundle) async {
        guard state != .loading else { return }
        guard let configuration = await resolveConfiguration() else {
            state = .failed(ReportAnalysisError.notConfigured.description)
            return
        }
        state = .loading
        shownRecordID = nil
        let locale = locale
        let request: ReportAnalysisRequest
        do {
            request = try await Task.detached(priority: .userInitiated) {
                try ReportAnalysisRequest(bundle: bundle, locale: locale)
            }.value
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        let sha = request.sha256
        do {
            let reply = try await client.analyze(request, model: configuration.model, apiKey: configuration.apiKey)
            if let violation = ReportAnalysisValidator.violation(in: reply) {
                let reason = ReportAnalysisError.rejected(term: violation.term).description
                await record(bundle, configuration, sha: sha, status: .rejected, response: nil, error: reason)
                state = .rejected(reason)
            } else {
                await record(bundle, configuration, sha: sha, status: .succeeded, response: Self.encode(reply), error: nil)
                state = .done(reply)
            }
        } catch {
            let reason = Self.message(for: error)
            await record(bundle, configuration, sha: sha, status: .failed, response: nil, error: reason)
            state = .failed(reason)
        }
        await refreshHistory(for: bundle.period)
    }

    // MARK: - Historial

    /// Muestra un análisis guardado. Los `rejected` y `failed` no tienen respuesta que mostrar.
    func show(_ record: ReportAnalysisRecord) {
        guard state != .loading else { return }
        switch record.status {
        case .succeeded:
            if let reply = Self.decode(record.responseJSON) {
                shownRecordID = record.id
                state = .done(reply)
            } else {
                state = .failed(String(localized: "reports.analysis.error.unreadable", defaultValue: "No se pudo leer el análisis guardado."))
            }
        case .rejected:
            state = .rejected(record.error ?? ReportAnalysisError.rejected(term: "").description)
        case .failed:
            state = .failed(record.error ?? "")
        }
    }

    func delete(_ record: ReportAnalysisRecord) async {
        _ = try? await store.deleteReportAnalysis(id: record.id)
        history.removeAll { $0.id == record.id }
        if shownRecordID == record.id {
            shownRecordID = nil
            state = .idle
        }
    }

    func refreshHistory(for period: ReportPeriod) async {
        let days = Self.spanDays(start: period.start, end: period.end)
        let all = (try? await store.recentReportAnalyses(limit: Self.historyFetchLimit)) ?? []
        history = all.filter { Self.spanDays(start: $0.periodStart, end: $0.periodEnd) == days }
    }

    /// Días (redondeados hacia arriba) que cubre un período: agrupa los análisis de "7 días", "30 días"… de cualquier fecha.
    nonisolated static func spanDays(start: UTCInstant, end: UTCInstant) -> Int {
        max(1, Int((Double(end.epochSeconds - start.epochSeconds) / 86_400).rounded(.up)))
    }

    // MARK: - Interno

    private func resolveConfiguration() async -> ReportAnalysisConfiguration? {
        guard let provider = settings.selectedProvider(), let model = settings.selectedModel(for: provider),
              let key = try? await keys.key(for: provider), !key.isEmpty else { return nil }
        return ReportAnalysisConfiguration(provider: provider, model: model, apiKey: key)
    }

    private func record(_ bundle: ReportBundle, _ configuration: ReportAnalysisConfiguration, sha: String,
                        status: ReportAnalysisStatus, response: String?, error: String?) async {
        let record = ReportAnalysisRecord(
            id: makeID(), createdAt: UTCInstant(now()), periodStart: bundle.period.start, periodEnd: bundle.period.end,
            provider: configuration.provider.rawValue, model: configuration.model.id, requestSHA256: sha,
            responseJSON: response, status: status, error: error)
        try? await store.insertReportAnalysis(record)
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "reports.analysis.error.unknown", defaultValue: "Error desconocido al analizar el reporte.")
    }

    nonisolated static func encode(_ reply: ReportAnalysisReply) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(reply)).flatMap { String(data: $0, encoding: .utf8) }
    }

    nonisolated static func decode(_ json: String?) -> ReportAnalysisReply? {
        json.flatMap { try? JSONDecoder().decode(ReportAnalysisReply.self, from: Data($0.utf8)) }
    }
}
