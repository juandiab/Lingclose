import Foundation
@testable import LingoScan

actor InMemoryPairingStateStore: PairingStatePersisting {
    nonisolated let recoveryHook: any RecoveryExportHook
    private var states: [String: PairingState] = [:]
    private var secrets: [String: PairingSecrets] = [:]

    init(recoveryHook: any RecoveryExportHook) {
        self.recoveryHook = recoveryHook
    }

    func currentSessionID() -> String? {
        states.values.max { $0.activation.updatedAt < $1.activation.updatedAt }?.sessionID
    }

    func loadState(sessionID: String) -> PairingState? { states[sessionID] }

    func saveState(_ state: PairingState) { states[state.sessionID] = state }

    func loadSecrets(sessionID: String) -> PairingSecrets { secrets[sessionID] ?? PairingSecrets() }

    func saveSecrets(_ new: PairingSecrets, sessionID: String) {
        var merged = secrets[sessionID] ?? PairingSecrets()
        if let v = new.receiverID { merged.receiverID = v }
        if let v = new.pin { merged.pin = v }
        if let v = new.kAuth { merged.kAuth = v }
        if let v = new.bleAddress { merged.bleAddress = v }
        if let v = new.activationResponse { merged.activationResponse = v }
        if let v = new.serial { merged.serial = v }
        secrets[sessionID] = merged
    }
}
