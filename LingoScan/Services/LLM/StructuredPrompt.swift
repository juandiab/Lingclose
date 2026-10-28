/// Una petición de salida estructurada, independiente del proveedor: instrucciones, texto del usuario
/// y el esquema JSON estricto que debe cumplir la respuesta. Cada proveedor la traduce a su API
/// (herramienta forzada en Anthropic, `response_format` en Chat Completions, `responseMimeType` en Gemini).
struct StructuredPrompt {
    var system: String
    var userText: String
    /// Nombre de la herramienta (Anthropic) y del esquema (`json_schema.name` en OpenAI).
    var toolName: String
    var toolDescription: String
    var schemaName: String
    /// JSON Schema estricto: todas las claves requeridas, sin propiedades extra.
    var schema: [String: Any]
}
