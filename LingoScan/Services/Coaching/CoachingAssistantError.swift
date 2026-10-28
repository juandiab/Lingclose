import Foundation

/// Fallos de "Preguntar al asistente" que no vienen del proveedor (esos son `LLMError`).
enum CoachingAssistantError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case notConfigured

    var description: String {
        switch self {
        case .notConfigured:
            String(localized: "coaching.assistant.notConfigured", defaultValue: "No hay asistente configurado. Elige proveedor, clave y modelo en Ajustes → Asistente de comidas.")
        }
    }

    var errorDescription: String? { description }
}
