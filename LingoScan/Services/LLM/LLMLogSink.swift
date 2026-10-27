/// Destino de los mensajes de diagnóstico de los servicios LLM. Solo recibe proveedor, operación,
/// estado HTTP y tamaños: nunca la clave, la foto, la descripción ni el cuerpo de una respuesta.
protocol LLMLogSink: Sendable {
    func log(_ message: String)
}
