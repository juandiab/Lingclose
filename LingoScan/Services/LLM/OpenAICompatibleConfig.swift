import Foundation

/// Diferencias entre los proveedores con API compatible con Chat Completions de OpenAI.
struct OpenAICompatibleConfig: Sendable {
    enum OutputMode: Sendable {
        /// `response_format: {type: "json_schema", json_schema: {name, strict: true, schema}}`.
        case jsonSchemaStrict
        /// `response_format: {type: "json_object"}` (el esquema va en el prompt).
        case jsonObject
    }

    var provider: LLMProviderID
    /// Base terminada en la versión, p. ej. `https://api.openai.com/v1`.
    var baseURL: URL
    var outputMode: OutputMode
    /// `max_completion_tokens` (OpenAI) o `max_tokens` (resto).
    var maxTokensField: String
    /// Envía `reasoning_effort: "low"` a los modelos con `supportsReasoningControl`.
    var sendsReasoningEffort: Bool
    var extraHeaders: [String: String] = [:]

    var chatURL: URL { baseURL.appending(path: "chat/completions") }
    var modelsURL: URL { baseURL.appending(path: "models") }
}
