import Foundation

/// Estado del sensor en forma presentable. Un caso por estado de `ARQUITECTURA.md` §3.
enum SensorPresentationState: String, Sendable, Hashable, CaseIterable {
    case noSensor
    case identified
    case incompatible
    case readyToActivate
    case activating
    case pairing
    case authenticationFailed
    case warmingUp
    case streaming
    case stale
    case reconnecting
    case paired
    case ended

    /// Etiqueta corta para chips y filas.
    var title: String {
        switch self {
        case .noSensor: String(localized: "sensor.state.noSensor", defaultValue: "Sin sensor")
        case .identified: String(localized: "sensor.state.identified", defaultValue: "Sensor identificado")
        case .incompatible: String(localized: "sensor.state.incompatible", defaultValue: "No compatible")
        case .readyToActivate: String(localized: "sensor.state.readyToActivate", defaultValue: "Listo para activar")
        case .activating: String(localized: "sensor.state.activating", defaultValue: "Activando")
        case .pairing: String(localized: "sensor.state.pairing", defaultValue: "Emparejando")
        case .authenticationFailed: String(localized: "sensor.state.authenticationFailed", defaultValue: "Autenticación fallida")
        case .warmingUp: String(localized: "sensor.state.warmingUp", defaultValue: "Calentando")
        case .streaming: String(localized: "sensor.state.streaming", defaultValue: "Conectado")
        case .stale: String(localized: "sensor.state.stale", defaultValue: "Sin datos recientes")
        case .reconnecting: String(localized: "sensor.state.reconnecting", defaultValue: "Reconectando")
        case .paired: String(localized: "sensor.state.paired", defaultValue: "Emparejado")
        case .ended: String(localized: "sensor.state.ended", defaultValue: "Sesión terminada")
        }
    }

    /// Frase para VoiceOver dentro del valor combinado ("sensor conectado").
    var spokenPhrase: String {
        switch self {
        case .noSensor: String(localized: "sensor.spoken.noSensor", defaultValue: "sin sensor")
        case .identified: String(localized: "sensor.spoken.identified", defaultValue: "sensor identificado")
        case .incompatible: String(localized: "sensor.spoken.incompatible", defaultValue: "sensor no compatible")
        case .readyToActivate: String(localized: "sensor.spoken.readyToActivate", defaultValue: "sensor listo para activar")
        case .activating: String(localized: "sensor.spoken.activating", defaultValue: "activando el sensor")
        case .pairing: String(localized: "sensor.spoken.pairing", defaultValue: "emparejando el sensor")
        case .authenticationFailed: String(localized: "sensor.spoken.authenticationFailed", defaultValue: "autenticación del sensor fallida")
        case .warmingUp: String(localized: "sensor.spoken.warmingUp", defaultValue: "sensor calentando")
        case .streaming: String(localized: "sensor.spoken.streaming", defaultValue: "sensor conectado")
        case .stale: String(localized: "sensor.spoken.stale", defaultValue: "sensor sin datos recientes")
        case .reconnecting: String(localized: "sensor.spoken.reconnecting", defaultValue: "reconectando el sensor")
        case .paired: String(localized: "sensor.spoken.paired", defaultValue: "sensor emparejado")
        case .ended: String(localized: "sensor.spoken.ended", defaultValue: "sesión del sensor terminada")
        }
    }

    var systemImage: String {
        switch self {
        case .noSensor: "sensor"
        case .identified: "sensor.tag.radiowaves.forward"
        case .incompatible: "exclamationmark.triangle"
        case .readyToActivate: "checkmark.circle"
        case .activating: "bolt.horizontal.circle"
        case .pairing: "link"
        case .authenticationFailed: "exclamationmark.triangle"
        case .warmingUp: "thermometer.medium"
        case .streaming: "antenna.radiowaves.left.and.right"
        case .stale: "clock.badge.exclamationmark"
        case .reconnecting: "antenna.radiowaves.left.and.right"
        case .paired: "link"
        case .ended: "clock.badge.xmark"
        }
    }

    /// Tono semántico; la vista lo traduce a color sin depender solo del color (siempre hay icono y texto).
    var tone: Tone {
        switch self {
        case .streaming, .paired, .readyToActivate: .good
        case .stale, .reconnecting, .warmingUp, .activating, .pairing: .attention
        case .incompatible, .authenticationFailed: .error
        case .noSensor, .identified, .ended: .neutral
        }
    }

    enum Tone: Sendable {
        case good
        case attention
        case error
        case neutral
    }
}
