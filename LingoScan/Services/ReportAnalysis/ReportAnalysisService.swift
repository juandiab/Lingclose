import Foundation
import LingoCore
import Observation

/// Análisis de un reporte con IA (T-27d, D-30). **Una petición por toque, sin reintentos**, con el proveedor, la clave y
/// el modelo del asistente de comidas (D-19). Cada intento queda en `report_analyses` como `succeeded`, `rejected`
/// (el validador descartó la respuesta entera) o `failed`, con el SHA-256 del mensaje enviado. La clave solo se lee
/// del Llavero en el instante de enviar y nunca se guarda en el estado observable.
///
/// T-33: con los interruptores de `ReportAnalysisSharing` (apagados por defecto) añade al mensaje el contexto opcional
/// (comidas con nombre, sueño y pasos, perfil y composición corporal). Encender uno de Salud pide su permiso de lectura
/// en ese momento; `prepare` nunca pide permisos.
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
    /// Qué contexto opcional puede ver la IA (los mismos interruptores que Ajustes › Asistente con IA). La hoja lo
    /// enlaza a sus `Toggle` y llama a `sharingDidChange()` cuando cambia.
    var sharing: ReportAnalysisSharing

    var isConfigured: Bool { model != nil }

    @ObservationIgnored private let keys: LLMKeyStore
    @ObservationIgnored private let settings: LLMSettingsStore
    @ObservationIgnored private let store: any ReportAnalysisStoring
    @ObservationIgnored private let client: ReportAnalysisClient
    @ObservationIgnored private let locale: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeID: @Sendable () -> String
    @ObservationIgnored private let sharingSettings: LLMSettingsStore
    @ObservationIgnored private let contextLoader: ReportAnalysisContextLoader
    @ObservationIgnored private var preparedPeriod: ReportPeriod?
    @ObservationIgnored private var preparedBundle: ReportBundle?
    /// Eventos del período abierto (para nombres de comidas); los da Reportes al abrir la hoja.
    @ObservationIgnored private var preparedEvents: [DiaryEvent] = []

    static let historyFetchLimit = 200

    init(keys: LLMKeyStore, settings: LLMSettingsStore, store: any ReportAnalysisStoring,
         client: ReportAnalysisClient = ReportAnalysisClient(), locale: String = Locale.current.identifier,
         sharingSettings: LLMSettingsStore? = nil, context: ReportAnalysisContextLoader = .unavailable,
         now: @escaping @Sendable () -> Date = { Date() },
         makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.keys = keys
        self.settings = settings
        self.sharingSettings = sharingSettings ?? settings
        self.contextLoader = context
        sharing = (sharingSettings ?? settings).analysisSharing()
        self.store = store
        self.client = client
        self.locale = locale
        self.now = now
        self.makeID = makeID
    }

    /// App real: claves y ajustes del asistente de comidas, red real, análisis en SQLite.
    static func live(store: SQLiteStore, assistant: MealAssistantServices) -> ReportAnalysisService {
        ReportAnalysisService(
            keys: assistant.keys, settings: assistant.settings, store: store,
            context: ReportAnalysisContextLoader(nutrition: assistant.nutrition, health: .live))
    }

    /// Sin asistente configurado ni almacén real: previsualizaciones. Los interruptores son los de `sharingSettings`
    /// (los del asistente de la previsualización, para que Ajustes y la hoja muestren lo mismo); comidas y Salud son
    /// inventadas. Con `-previewAnalysis YES` (DEBUG) aparece configurado con una clave falsa y sin red, para ver
    /// "Qué se enviará" en el simulador: "Analizar" falla sin llamar a ningún proveedor.
    static func preview(sharingSettings: LLMSettingsStore = MealAssistantServices.preview.settings) -> ReportAnalysisService {
        let settings = LLMSettingsStore(defaults: UserDefaults(suiteName: "report-analysis-preview") ?? .standard)
        var fakeKey: String?
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "previewAnalysis") {
            fakeKey = "preview-not-a-key"
            settings.setSelectedProvider(.anthropic)
            settings.setSelectedModel(LLMModel(
                id: LLMCatalog.defaultAnthropicModel, provider: .anthropic, displayName: "Claude Haiku 5.5",
                pricing: LLMCatalog.entry(provider: .anthropic, modelID: LLMCatalog.defaultAnthropicModel)?.pricing))
        }
        #endif
        let key = fakeKey
        return ReportAnalysisService(
            keys: LLMKeyStore(itemFor: { _ in PreviewSecretItem(value: key) }),
            settings: settings, store: PreviewReportAnalysisStore(),
            client: ReportAnalysisClient(transport: PreviewOfflineTransport()),
            sharingSettings: sharingSettings, context: .preview)
    }

    // MARK: - Preparar la hoja

    /// Al abrir la hoja de un reporte: reinicia el estado si cambió de período, relee la configuración y los
    /// interruptores, calcula lo que se enviará (con el contexto opcional encendido) y carga el historial. No envía
    /// nada ni pide permisos.
    func prepare(for bundle: ReportBundle, events: [DiaryEvent] = []) async {
        if preparedPeriod != bundle.period {
            if state != .loading { state = .idle }
            shownRecordID = nil
            outgoing = nil
        }
        preparedPeriod = bundle.period
        preparedBundle = bundle
        preparedEvents = events
        sharing = sharingSettings.analysisSharing()
        await refreshConfiguration()
        await refreshHistory(for: bundle.period)
        await refreshOutgoing()
    }

    /// Enciende o apaga un interruptor del contexto opcional (los mismos que en Ajustes). Al encender uno de Salud pide
    /// su permiso de lectura; después recalcula "Qué se enviará".
    func setSharing(_ option: ReportAnalysisSharingOption, isOn: Bool) async {
        sharing.set(option, isOn)
        await sharingDidChange()
    }

    /// Guarda los interruptores que cambiaron respecto a lo guardado, pide el permiso de Salud de los que se
    /// encendieron y recalcula "Qué se enviará". Sin cambios (p. ej. al releerlos en `prepare`) no hace nada.
    func sharingDidChange() async {
        let stored = sharingSettings.analysisSharing()
        let changed = ReportAnalysisSharingOption.allCases.filter { stored[$0] != sharing[$0] }
        guard !changed.isEmpty else { return }
        for option in changed {
            sharingSettings.setAnalysisSharing(option, isOn: sharing[option])
        }
        for option in changed where sharing[option] {
            await contextLoader.health.requestAccess(for: option)
        }
        await refreshOutgoing()
    }

    /// Recalcula el tamaño y el coste de lo que se enviará con los interruptores actuales.
    func refreshOutgoing() async {
        guard let model, let bundle = preparedBundle else {
            outgoing = nil
            return
        }
        let sharing = sharing
        let request = try? await Self.makeRequest(bundle: bundle, events: preparedEvents, locale: locale,
                                                  sharing: sharing, loader: contextLoader)
        // Si mientras tanto cambió algo, otra llamada ya está calculando lo vigente.
        guard sharing == self.sharing, bundle == preparedBundle else { return }
        outgoing = request.map { ReportAnalysisPreview(request: $0, model: model, sharing: sharing) }
    }

    /// Snapshot compactado, contexto opcional (con el mismo snapshot) y petición, fuera del hilo principal.
    nonisolated static func makeRequest(bundle: ReportBundle, events: [DiaryEvent], locale: String,
                                        sharing: ReportAnalysisSharing,
                                        loader: ReportAnalysisContextLoader) async throws -> ReportAnalysisRequest {
        let snapshot = await Task.detached(priority: .userInitiated) { bundle.snapshot.compact() }.value
        let context = await loader.load(snapshot: snapshot, events: events, period: bundle.period, sharing: sharing)
        return try await Task.detached(priority: .userInitiated) {
            try ReportAnalysisRequest(bundle: bundle, snapshot: snapshot, locale: locale, context: context)
        }.value
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
    func analyze(_ bundle: ReportBundle, events: [DiaryEvent]? = nil) -> Task<Void, Never> {
        Task { await run(bundle, events: events) }
    }

    /// `events` `nil`: los del período preparado (si es el mismo), para no perder los nombres de comidas.
    func run(_ bundle: ReportBundle, events: [DiaryEvent]? = nil) async {
        guard state != .loading else { return }
        guard let configuration = await resolveConfiguration() else {
            state = .failed(ReportAnalysisError.notConfigured.description)
            return
        }
        state = .loading
        shownRecordID = nil
        let events = events ?? (preparedPeriod == bundle.period ? preparedEvents : [])
        let request: ReportAnalysisRequest
        do {
            request = try await Self.makeRequest(bundle: bundle, events: events, locale: locale,
                                                 sharing: sharing, loader: contextLoader)
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
