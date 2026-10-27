import RoundWhiteDiscKit

/// Fase visible del emparejamiento. Las fases del handshake son las de `AuthPhase`
/// del fork; se añaden activación NFC, conexión y suscripción del plano de datos.
enum PairingPhase: String, Sendable, Equatable, Codable {
    case activation
    case connecting
    case certificateLoad
    case certificateAcceptance
    case sensorCertificate
    case ephemeral
    case challenge
    case phase6
    case subscribing

    init(_ phase: AuthPhase) {
        switch phase {
        case .certificateLoad: self = .certificateLoad
        case .certificateAcceptance: self = .certificateAcceptance
        case .sensorCertificate: self = .sensorCertificate
        case .ephemeral: self = .ephemeral
        case .challenge: self = .challenge
        case .phase6: self = .phase6
        }
    }

    /// Fase de un `PairingFlowError.writeTimeout` según su etiqueta (`PairingFlow.swift`).
    init(writeTimeoutLabel label: String) {
        switch label {
        case "StartAuthentication", "LoadCertificate", "phoneCertWrite", "SendCertificateLoadDone":
            self = .certificateLoad
        case "GetCertificate", "ValidateCertificate":
            self = .sensorCertificate
        case "phoneEphemeralWrite", "SendEphemeralDone":
            self = .ephemeral
        case "StartAuthorization":
            self = .challenge
        default:
            self = .phase6
        }
    }
}
