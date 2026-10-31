/// Proveedor, modelo y clave con los que se enviará el análisis: los del asistente de comidas (D-19).
struct ReportAnalysisConfiguration: Sendable {
    var provider: LLMProviderID
    var model: LLMModel
    var apiKey: String

    /// Nombre legible para mostrar, p. ej. "Anthropic (Claude) · claude-sonnet-5-5". Nunca la clave.
    var label: String { "\(provider.displayName) · \(model.displayName)" }
}
