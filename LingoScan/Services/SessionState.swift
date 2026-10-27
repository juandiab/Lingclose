import Foundation
import LingoCore

/// Máquina de estados del sensor (`ARQUITECTURA.md` §3).
enum SessionState: Sendable, Equatable {
    case noSensor
    case identified(SensorProfile)
    case incompatible(SensorProfile, reason: IncompatibilityReason)
    case readyToActivate(SensorProfile)
    case activating
    case pairing(PairingPhase)
    case warmingUp(remainingMinutes: Int)
    case streaming(last: ReadingSummary)
    case stale(since: Date)
    case reconnecting(attempt: Int)
    case ended(reason: SessionEndReason)
    case authenticationFailed(PairingPhase, reason: AuthenticationFailureReason)
    /// Rol de recolectora transferido (`RECUPERACION_V1.md` §6): sin reconexión,
    /// sin restauración de CoreBluetooth y sin escritura en Health.
    case paused

    /// Solo con la sesión viva la app escribe en Health.
    var allowsHealthExport: Bool {
        switch self {
        case .warmingUp, .streaming, .stale, .reconnecting: true
        default: false
        }
    }

    /// Etiqueta sin datos sensibles para `event_log`.
    var logLabel: String {
        switch self {
        case .noSensor: "noSensor"
        case .identified(let p): "identified(\(p.family.rawValue), state \(p.stateByte))"
        case .incompatible(_, let reason): "incompatible(\(reason))"
        case .readyToActivate: "readyToActivate"
        case .activating: "activating"
        case .pairing(let phase): "pairing(\(phase.rawValue))"
        case .warmingUp(let minutes): "warmingUp(\(minutes) min)"
        case .streaming(let last): "streaming(lc \(last.lifeCount), elegible \(last.eligible))"
        case .stale: "stale"
        case .reconnecting(let attempt): "reconnecting(\(attempt))"
        case .ended(let reason): "ended(\(reason.rawValue))"
        case .authenticationFailed(let phase, let reason): "authenticationFailed(\(phase.rawValue), \(reason.summary))"
        case .paused: "paused"
        }
    }
}
