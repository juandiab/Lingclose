import Foundation

/// Por qué el botón "Activar sensor" está deshabilitado. El pie de la sección lo explica.
enum ActivationBlocker: Sendable, Hashable {
    case sensorNotRead
    case unsupportedVariant
    case noLingoIdentity
    case noSigningKeys
    case actionsUnavailable

    var explanation: String {
        switch self {
        case .sensorNotRead:
            String(localized: "activation.blocker.notRead", defaultValue: "Primero lee el sensor por NFC: solo se activa un Lingo sin activar (state 1).")
        case .unsupportedVariant:
            String(localized: "activation.blocker.variant", defaultValue: "Este sensor no es un Lingo compatible (productType 9, securityVersion 3).")
        case .noLingoIdentity:
            String(localized: "activation.blocker.identity", defaultValue: "Falta una identidad de app que sirva a Lingo. Impórtala en Ajustes.")
        case .noSigningKeys:
            String(localized: "activation.blocker.keys", defaultValue: "La identidad no trae claves de firma del sensor. Sin ellas no se empareja.")
        case .actionsUnavailable:
            String(localized: "activation.blocker.unavailable", defaultValue: "La activación no está disponible en este modo.")
        }
    }
}
