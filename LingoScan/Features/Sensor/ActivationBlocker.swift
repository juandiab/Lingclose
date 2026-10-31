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
            String(localized: "activation.blocker.notRead", defaultValue: "Primero lee el biosensor por NFC. Solo se puede activar un biosensor (Abbott Lingo) que todavía no esté activado.")
        case .unsupportedVariant:
            String(localized: "activation.blocker.variant", defaultValue: "Este biosensor no es compatible. Lingclose funciona con Abbott Lingo.")
        case .noLingoIdentity:
            String(localized: "activation.blocker.identity", defaultValue: "Falta una identidad del biosensor compatible con Abbott Lingo. Impórtala en Ajustes › Avanzado › Identidad del sensor.")
        case .noSigningKeys:
            String(localized: "activation.blocker.keys", defaultValue: "La identidad no trae claves de firma del sensor. Sin ellas no se empareja.")
        case .actionsUnavailable:
            String(localized: "activation.blocker.unavailable", defaultValue: "La activación no está disponible en este modo.")
        }
    }
}
