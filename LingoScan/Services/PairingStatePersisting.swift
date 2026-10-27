import Foundation
import LingoCore

/// Persistencia del pairing por `session_id`. `PairingStateStore` es la real;
/// los tests usan una en memoria.
protocol PairingStatePersisting: Sendable {
    var recoveryHook: any RecoveryExportHook { get }

    /// Sesión más reciente (por `activation.updatedAt`), si hay.
    func currentSessionID() async throws -> String?
    func loadState(sessionID: String) async throws -> PairingState?
    func saveState(_ state: PairingState) async throws
    func loadSecrets(sessionID: String) async throws -> PairingSecrets
    /// Escribe solo los campos no `nil`.
    func saveSecrets(_ secrets: PairingSecrets, sessionID: String) async throws
}

extension PairingStatePersisting {
    /// Crea la sesión en `prepared` y llama al hook. Se usa antes de mostrar el ticket.
    func begin(_ state: PairingState) async throws {
        precondition(state.activation.state == .prepared, "una sesión nueva empieza en prepared")
        try await saveState(state)
        await recoveryHook.recoveryCheckpoint(state.activation)
    }

    /// Persiste la transición y, en `prepared`/`response_saved`/`authenticated`, llama al hook
    /// después de guardar.
    @discardableResult
    func transition(
        sessionID: String,
        to next: ActivationState,
        reason: String? = nil,
        now: Date
    ) async throws -> ActivationRecord {
        guard var state = try await loadState(sessionID: sessionID) else {
            throw ActivationTransitionError.unknownSession
        }
        state.activation = try state.activation.advancing(to: next, reason: reason, now: now)
        try await saveState(state)
        if ActivationRecord.exportStates.contains(next) {
            await recoveryHook.recoveryCheckpoint(state.activation)
        }
        return state.activation
    }
}
