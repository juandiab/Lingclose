import Foundation

/// Errores del análisis con LLM. Ningún caso lleva la clave ni el cuerpo de la petición: los textos
/// que vienen del proveedor se recortan y se les borra la clave antes de llegar aquí (`LLMHTTP`).
enum LLMError: Error, Sendable, Hashable {
    case unauthorized
    case quotaExceeded
    case rateLimited
    case refused(String)
    case incomplete(String)
    case modelLacksVision
    case network(String)
    case server(status: Int, message: String)
    case invalidResponse(String)
}

extension LLMError: CustomStringConvertible, LocalizedError {
    var description: String {
        switch self {
        case .unauthorized:
            String(localized: "llm.error.unauthorized",
                   defaultValue: "La clave no es válida o no tiene permiso para este servicio.")
        case .quotaExceeded:
            String(localized: "llm.error.quotaExceeded",
                   defaultValue: "La cuenta no tiene saldo o cuota disponible para analizar.")
        case .rateLimited:
            String(localized: "llm.error.rateLimited",
                   defaultValue: "Demasiadas peticiones seguidas. Espera un momento antes de volver a intentarlo.")
        case .refused(let reason):
            String(localized: "llm.error.refused", defaultValue: "El modelo se negó a analizar el contenido (\(reason)).")
        case .incomplete(let reason):
            String(localized: "llm.error.truncated",
                   defaultValue: "La respuesta llegó incompleta (\(reason)). No se reintentó para no cobrar dos veces.")
        case .modelLacksVision:
            String(localized: "llm.error.modelLacksVision",
                   defaultValue: "Este modelo no tiene lectura de imágenes confirmada. Elige otro modelo o describe la comida con texto.")
        case .network(let detail):
            String(localized: "llm.error.network", defaultValue: "No se pudo conectar con el proveedor (\(detail)).")
        case .server(let status, let message):
            String(localized: "llm.error.server", defaultValue: "El proveedor respondió con el error \(status): \(message)")
        case .invalidResponse(let detail):
            String(localized: "llm.error.invalidResponse",
                   defaultValue: "La respuesta del modelo no tiene el formato esperado (\(detail)).")
        }
    }

    var errorDescription: String? { description }
}
