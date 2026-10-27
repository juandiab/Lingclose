import Foundation

extension PairingPhase {
    /// Nombre de la fase para la pantalla Sensor.
    var displayName: String {
        switch self {
        case .activation: String(localized: "pairing.phase.activation", defaultValue: "Activación NFC")
        case .connecting: String(localized: "pairing.phase.connecting", defaultValue: "Conexión Bluetooth")
        case .certificateLoad: String(localized: "pairing.phase.certificateLoad", defaultValue: "Envío del certificado de la app")
        case .certificateAcceptance: String(localized: "pairing.phase.certificateAcceptance", defaultValue: "Aceptación del certificado de la app")
        case .sensorCertificate: String(localized: "pairing.phase.sensorCertificate", defaultValue: "Certificado del sensor")
        case .ephemeral: String(localized: "pairing.phase.ephemeral", defaultValue: "Intercambio de claves")
        case .challenge: String(localized: "pairing.phase.challenge", defaultValue: "Desafío")
        case .phase6: String(localized: "pairing.phase.phase6", defaultValue: "Fase 6")
        case .subscribing: String(localized: "pairing.phase.subscribing", defaultValue: "Suscripción de datos")
        }
    }
}
