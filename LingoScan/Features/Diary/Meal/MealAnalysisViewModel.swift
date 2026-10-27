import Foundation
import LingoCore
import Observation

/// Registro de una comida con propuesta de un LLM (T-21): entrada (foto y/o descripción), una sola llamada
/// al proveedor, propuesta editable y guardado. También reabre una comida guardada con su base, su
/// multiplicador y sus correcciones. Nada se guarda solo: `save()` solo lo llama el botón "Guardar".
///
/// Las cifras mostradas salen siempre de `PortionAdjustment.adjusted(base, multiplier:, overrides:)`: el
/// slider nunca llama al proveedor y la base nunca se reescribe.
@MainActor
@Observable
final class MealAnalysisViewModel: Identifiable {
    enum Phase: Equatable {
        case input
        case analyzing
        case failed(String)
        case proposal
    }

    enum Readiness: Equatable {
        case checking
        case notConfigured
        case ready(LLMModel)
    }

    enum SaveFailure: Equatable {
        case failed
        case conflict
    }

    let id = UUID()

    // MARK: Entrada
    var descriptionText: String
    private(set) var photoJPEG: Data?
    var at: Date
    private(set) var phase: Phase
    private(set) var readiness: Readiness = .checking

    // MARK: Propuesta
    private(set) var kind: FoodAnalysisKind = .food
    var name = ""
    private(set) var basis: PortionBasis?
    private(set) var baseNutrients = Nutrients.unknown
    private(set) var multiplier = NutrientLimits.defaultPortionMultiplier
    private(set) var overrides = Nutrients.unknown
    private(set) var assumptions: String?
    private(set) var confidence: Double?
    private(set) var unreadableFields: [String] = []
    /// Aviso al reabrir cuando el evento cambió fuera de la app (p. ej. una importación más nueva).
    private(set) var externalChangeNotice: String?

    // MARK: Guardado
    private(set) var isSaving = false
    private(set) var saveFailure: SaveFailure?
    private(set) var didSave = false

    /// Evento que se edita (reabrir o análisis sobre un registro existente); `nil` en un alta.
    let editing: DiaryEvent?

    @ObservationIgnored private(set) var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var source: MealNutritionSource?
    @ObservationIgnored private var analyzedAt: UTCInstant?
    /// Texto tal como lo teclea el usuario en cada campo (se descarta al salir del campo si no hay corrección).
    private var rawEdits: [NutrientField: String] = [:]

    @ObservationIgnored private let services: MealAssistantServices
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let newID: @Sendable () -> String

    /// Desde el "+" de Hoy → Comida: abrir la cámara al entrar y analizar en cuanto haya foto (un solo botón).
    private(set) var autoCameraPending = false
    private var autoAnalyzeOnNextPhoto = false

    /// Alta de una comida (o análisis sobre un evento sin fila de nutrición).
    init(
        services: MealAssistantServices,
        editing: DiaryEvent? = nil,
        at: Date,
        initialDescription: String? = nil,
        autoCamera: Bool = false,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.services = services
        self.editing = editing
        self.at = at
        self.calendar = calendar
        self.now = now
        self.newID = newID
        descriptionText = initialDescription ?? ""
        phase = .input
        autoCameraPending = autoCamera
    }

    /// La vista lo consume una sola vez al mostrar la entrada: `true` = abrir la cámara ahora. La foto que
    /// llegue de esa cámara lanza el análisis sin otro toque.
    func consumeAutoCamera() -> Bool {
        guard autoCameraPending else { return false }
        autoCameraPending = false
        autoAnalyzeOnNextPhoto = true
        return true
    }

    /// La cámara automática se cerró sin foto: la siguiente foto ya no analiza sola.
    func cameraCancelled() {
        autoAnalyzeOnNextPhoto = false
    }

    /// Reabre una comida guardada: base, multiplicador y correcciones cargados.
    init(
        reopening event: DiaryEvent,
        record: MealNutritionRecord,
        services: MealAssistantServices,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.services = services
        editing = event
        at = event.at.date
        self.calendar = calendar
        self.now = now
        self.newID = newID
        descriptionText = ""
        phase = .proposal
        kind = record.kind
        name = record.name ?? event.text ?? ""
        basis = record.basis
        baseNutrients = record.baseNutrients
        multiplier = PortionAdjustment.clamp(record.multiplier)
        overrides = record.overrides
        assumptions = record.assumptions
        confidence = record.confidence
        source = record.source
        analyzedAt = record.analyzedAt
        let stored = record.effectiveNutrients.carbsG
        if !Self.sameCarbs(event.carbsG, stored) {
            externalChangeNotice = Self.changeNotice(eventCarbs: event.carbsG)
        }
    }

    // MARK: Configuración del asistente

    /// Lee el proveedor y el modelo elegidos en Ajustes y comprueba que haya clave.
    func prepare() async {
        guard let provider = services.settings.selectedProvider(),
              let model = services.settings.selectedModel(for: provider),
              await services.keys.hasKey(for: provider) else {
            readiness = .notConfigured
            return
        }
        readiness = .ready(model)
    }

    var model: LLMModel? {
        if case .ready(let model) = readiness { model } else { nil }
    }

    // MARK: Entrada y análisis

    func setPhoto(_ jpeg: Data?) {
        photoJPEG = jpeg
        if jpeg != nil, autoAnalyzeOnNextPhoto {
            autoAnalyzeOnNextPhoto = false
            startAnalysis()
        }
    }

    var trimmedDescription: String? {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var hasInput: Bool { photoJPEG != nil || trimmedDescription != nil }

    /// Hay foto pero el modelo elegido no tiene lectura de imágenes confirmada: solo se puede analizar la descripción.
    var photoBlockedByModel: Bool {
        guard photoJPEG != nil, let model else { return false }
        return model.imageSupport != .confirmed
    }

    var canAnalyze: Bool {
        guard model != nil, hasInput, !photoBlockedByModel else { return false }
        switch phase {
        case .input, .failed: return true
        case .analyzing, .proposal: return false
        }
    }

    /// Quita la foto para analizar solo la descripción.
    func discardPhoto() {
        photoJPEG = nil
    }

    /// Lanza el análisis en una `Task` que `cancelAnalysis()` puede cancelar.
    func startAnalysis() {
        guard canAnalyze else { return }
        phase = .analyzing
        analysisTask = Task { await analyze() }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        if phase == .analyzing { phase = .input }
    }

    /// Un análisis = una llamada al proveedor. Sin reintentos automáticos: tras un error solo el usuario reintenta.
    func analyze() async {
        guard !Task.isCancelled, let model, canAnalyze || phase == .analyzing else { return }
        phase = .analyzing
        // Solo la foto reducida y la descripción: nada de glucosa, Salud ni entrenamientos.
        let request = FoodAnalysisRequest(imageJPEG: photoJPEG, description: trimmedDescription)
        do {
            guard let apiKey = try await services.keys.key(for: model.provider) else {
                fail(LLMError.unauthorized)
                return
            }
            let analysis = try await services.makeProvider(model.provider).analyze(request, model: model, apiKey: apiKey)
            guard !Task.isCancelled else { return }
            apply(analysis, model: model)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func fail(_ error: any Error) {
        let message = (error as? LLMError)?.description
            ?? String(localized: "meal.error.unexpected", defaultValue: "Ocurrió un error inesperado al analizar.")
        phase = .failed(message)
    }

    private func apply(_ analysis: FoodAnalysis, model: LLMModel) {
        kind = analysis.kind
        name = analysis.name ?? trimmedDescription ?? ""
        basis = analysis.basis
        baseNutrients = analysis.baseNutrients
        multiplier = NutrientLimits.defaultPortionMultiplier
        overrides = .unknown
        rawEdits = [:]
        assumptions = analysis.assumptions
        confidence = analysis.confidence
        unreadableFields = analysis.unreadableFields
        analyzedAt = UTCInstant(now())
        source = analysis.kind == .nutritionLabel
            ? .label(provider: model.provider.rawValue, model: model.id)
            : .llm(provider: model.provider.rawValue, model: model.id)
        phase = .proposal
    }

    /// Vuelve de la propuesta a la entrada (conserva foto y descripción).
    func backToInput() {
        phase = .input
    }

    // MARK: Cifras

    /// `true` si hay alguna cifra base con la que el slider tiene sentido.
    var hasFigures: Bool { !baseNutrients.isUnknown }

    /// Base × multiplicador, sin correcciones: lo que "Restablecer" recupera.
    var calculated: Nutrients { baseNutrients.scaled(by: multiplier) }

    /// Lo que se mostrará y se guardará como efectivo: `overrides[f] ?? base[f] × multiplicador`.
    var adjusted: Nutrients {
        PortionAdjustment.adjusted(baseNutrients, multiplier: multiplier, overrides: overrides)
    }

    /// Para `@Bindable`: el slider escribe aquí y siempre pasa por `setMultiplier`.
    var sliderValue: Double {
        get { multiplier }
        set { setMultiplier(newValue) }
    }

    /// Para `@Bindable`: `$model[text: field]`.
    subscript(text field: NutrientField) -> String {
        get { text(for: field) }
        set { setText(newValue, for: field) }
    }

    func setMultiplier(_ value: Double) {
        multiplier = PortionAdjustment.clamp(value)
    }

    /// "1,5" (coma decimal, siempre un decimal).
    var multiplierText: String {
        let tenths = Int((multiplier * 10).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }

    func isManual(_ field: NutrientField) -> Bool { overrides[field] != nil }

    /// Texto tecleado y no válido (no numérico o fuera de rango): bloquea el guardado.
    func isInvalid(_ field: NutrientField) -> Bool {
        guard let raw = rawEdits[field]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return false }
        return overrides[field] == nil
    }

    func text(for field: NutrientField) -> String {
        if let raw = rawEdits[field] { return raw }
        return PortionAdjustment.display(adjusted[field], field: field) ?? ""
    }

    /// Corrección manual de un campo. Vacío o inválido = sin corrección (nunca 0). Lo corregido a mano no lo
    /// toca el slider.
    func setText(_ text: String, for field: NutrientField) {
        rawEdits[field] = text
        if let value = DiaryDraft.parse(text), NutrientLimits.range(for: field).contains(value) {
            overrides[field] = value
        } else {
            overrides[field] = nil
        }
    }

    /// Al salir del campo: si no quedó corrección, vuelve a mostrar el valor calculado.
    func commitEditing(_ field: NutrientField) {
        if overrides[field] != nil || isInvalid(field) { return }
        rawEdits[field] = nil
    }

    func reset(_ field: NutrientField) {
        overrides[field] = nil
        rawEdits[field] = nil
    }

    // MARK: Textos de la propuesta

    var basisSummary: String? {
        guard let basis else { return nil }
        let adjust = hasFigures
            ? String(localized: "meal.basis.adjust", defaultValue: "; ajusta las porciones abajo")
            : ""
        switch basis {
        case .per100g:
            return String(localized: "meal.basis.per100g", defaultValue: "Valores por 100 g de la etiqueta") + adjust
        case .per100ml:
            return String(localized: "meal.basis.per100ml", defaultValue: "Valores por 100 ml de la etiqueta") + adjust
        case .perServing(let description, let grams):
            let detail = Self.servingDetail(description: description, grams: grams)
            return String(localized: "meal.basis.perServing", defaultValue: "Valores por porción de la etiqueta") + detail + adjust
        case .estimatedServing(let description, let grams):
            let detail = Self.servingDetail(description: description, grams: grams)
            return String(localized: "meal.basis.estimated", defaultValue: "Porción estimada") + detail
        }
    }

    private static func servingDetail(description: String?, grams: Double?) -> String {
        let g = PortionAdjustment.display(grams, field: .carbsG).map { "\($0) g" }
        switch (description, g) {
        case let (d?, g?): return ": \(d) (\(g))"
        case let (d?, nil): return ": \(d)"
        case let (nil, g?): return ": \(g)"
        case (nil, nil): return ""
        }
    }

    var confidenceText: String? {
        guard let confidence else { return nil }
        let percent = String(Int((confidence * 100).rounded()))
        return String(localized: "meal.confidence", defaultValue: "Confianza: \(percent) %")
    }

    var unreadableText: String? {
        guard !unreadableFields.isEmpty else { return nil }
        let list = unreadableFields.joined(separator: ", ")
        return String(localized: "meal.unreadable", defaultValue: "No legible: \(list)")
    }

    private static func sameCarbs(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a - b) < 0.05
        default: false
        }
    }

    private static func changeNotice(eventCarbs: Double?) -> String {
        if let eventCarbs, let text = PortionAdjustment.display(eventCarbs, field: .carbsG) {
            return String(localized: "meal.changedOutside", defaultValue: "Este registro cambió fuera de la app; los carbohidratos guardados son \(text) g")
        }
        return String(localized: "meal.changedOutside.none", defaultValue: "Este registro cambió fuera de la app; ya no tiene carbohidratos guardados")
    }

    // MARK: Guardar

    var canSave: Bool {
        guard phase == .proposal, kind != .notFood, !isSaving else { return false }
        return !NutrientField.allCases.contains { isInvalid($0) }
    }

    /// Construye el evento de comida y el registro de nutrición y los guarda juntos. Devuelve `true` si
    /// quedaron como versión actual.
    @discardableResult
    func save() async -> Bool {
        guard canSave, let source else { return false }
        isSaving = true
        saveFailure = nil
        defer { isSaving = false }
        let instant = UTCInstant(now())
        let eventID = editing?.eventID ?? newID()
        let record = MealNutritionRecord(
            eventID: eventID, source: source, kind: kind, name: trimmedName,
            basis: basis ?? .estimatedServing(description: nil, grams: nil),
            baseNutrients: baseNutrients, multiplier: multiplier, overrides: overrides,
            assumptions: assumptions, confidence: confidence, analyzedAt: analyzedAt, updatedAt: instant)
        let event = makeEvent(id: eventID, text: trimmedName, carbs: record.effectiveNutrients.carbsG, instant: instant)
        do {
            switch try await services.nutrition.saveMeal(event: event, nutrition: record) {
            case .inserted, .tookDescendant, .unchanged:
                didSave = true
                return true
            case .keptNewerLocal, .divergent, .lineageUnknown:
                saveFailure = .conflict
                return false
            }
        } catch {
            saveFailure = .failed
            return false
        }
    }

    private var trimmedName: String? {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Mismo linaje que `DiaryViewModel.save`: edición nueva con `parent_edit_id` = la anterior.
    private func makeEvent(id: String, text: String?, carbs: Double?, instant: UTCInstant) -> DiaryEvent {
        if let previous = editing {
            return DiaryEvent(
                eventID: id, kind: .meal, at: UTCInstant(at), tz: calendar.timeZone.identifier,
                carbsG: carbs, text: text,
                createdAt: previous.createdAt, updatedAt: instant, revision: previous.revision + 1,
                editID: newID(), parentEditID: previous.editID, editedByAppID: DiaryViewModel.appID,
                deleted: false, synthetic: false)
        }
        return DiaryEvent(
            eventID: id, kind: .meal, at: UTCInstant(at), tz: calendar.timeZone.identifier,
            carbsG: carbs, text: text,
            createdAt: instant, updatedAt: instant, revision: 1,
            editID: newID(), parentEditID: nil, editedByAppID: DiaryViewModel.appID,
            deleted: false, synthetic: false)
    }
}
