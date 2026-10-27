import Foundation
import LingoCore

/// Registro durable del intento de activación (`RECUPERACION_V1.md` §4). Cada
/// transición incrementa `sequence` y se persiste antes del paso irreversible
/// que la sigue.
struct ActivationRecord: Sendable, Equatable, Codable {
    let sessionID: String
    let attemptID: String
    private(set) var state: ActivationState
    private(set) var sequence: Int
    private(set) var failureReason: String?
    private(set) var updatedAt: Date

    /// Estados tras los que se invoca `RecoveryExportHook`.
    static let exportStates: Set<ActivationState> = [.prepared, .responseSaved, .authenticated]

    static func prepared(sessionID: String, attemptID: String, now: Date) -> ActivationRecord {
        ActivationRecord(sessionID: sessionID, attemptID: attemptID, state: .prepared,
                         sequence: 1, failureReason: nil, updatedAt: now)
    }

    /// `prepared → sent → response_saved → authenticated`; `failed` desde los tres
    /// primeros; `authenticated → authenticated` cuando un handshake completo renueva kAuth.
    func advancing(to next: ActivationState, reason: String? = nil, now: Date) throws -> ActivationRecord {
        guard Self.isAllowed(from: state, to: next) else {
            throw ActivationTransitionError.notAllowed(from: state, to: next)
        }
        var copy = self
        copy.state = next
        copy.sequence += 1
        copy.failureReason = next == .failed ? reason : nil
        copy.updatedAt = now
        return copy
    }

    /// D-22 (Receiver ID por sensor, no por intento): un intento `failed` antes de que el sensor
    /// aceptara `0xA0` vuelve a `prepared` en la misma sesión, con `attempt_id` nuevo. Quien llama
    /// comprueba que no hay respuesta guardada y que una lectura `0xA1` reciente da `state 1`.
    func rearmed(attemptID newAttemptID: String, now: Date) throws -> ActivationRecord {
        guard state == .failed else {
            throw ActivationTransitionError.notAllowed(from: state, to: .prepared)
        }
        return ActivationRecord(sessionID: sessionID, attemptID: newAttemptID, state: .prepared,
                                sequence: sequence + 1, failureReason: nil, updatedAt: now)
    }

    static func isAllowed(from: ActivationState, to: ActivationState) -> Bool {
        switch (from, to) {
        case (.prepared, .sent), (.sent, .responseSaved), (.responseSaved, .authenticated),
             (.authenticated, .authenticated),
             (.prepared, .failed), (.sent, .failed), (.responseSaved, .failed):
            true
        default:
            false
        }
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case attemptID = "attempt_id"
        case state = "activation_state"
        case sequence
        case failureReason = "failure_reason"
        case updatedAt = "updated_at"
    }
}
