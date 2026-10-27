/// Fusión pura de copias de recuperación (`RECUPERACION_V1.md` §5 paso 4, **draft.4**).
///
/// Orden de reglas por sesión remota:
/// 1. Identidad: mismo `session_id`, alias conocido, o mismo `sensor_serial_hash` con ambos tiempos de
///    activación conocidos y a ≤ 120 s (se añade el alias). Si falta un tiempo no se infiere equivalencia.
/// 2. Sesión desconocida → se importa entera.
/// 3. `attempt_id` distinto → intento histórico; la activa no cambia.
/// 4. Mismo intento: **primero** el conflicto de secretos (ambos valores no nulos y distintos en cualquier
///    `sequence`) → se conservan ambas copias íntegras, la local no cambia. `null` frente a valor no es conflicto.
/// 5. Sin conflicto: `sequence` remota mayor → copia remota entera; igual con otro exportador →
///    `updated_at_utc` posterior gana; en otro caso se conserva la local.
///
/// Campos inmutables de un intento (los cinco secretos de `secretPaths`) frente a valores que evolucionan
/// (`state`, `sequence`, `updated_at_utc`, `last_life_count`, marcas de handshake): solo los primeros
/// generan conflicto. Nada aquí ejecuta NFC ni BLE.
public enum RecoveryMerge {
    /// Secretos inmutables de un intento (§5 paso 4).
    public static let secretPaths = [
        "activation.receiver_id_used", "activation.response_hex", "ble.address", "ble.pin_hex", "auth.k_auth_hex",
    ]
    public static let equivalenceWindowSeconds: Int64 = 120

    /// Rutas de secreto con valores no nulos distintos en ambas copias.
    public static func conflictingSecrets(_ a: RecoveryPayload.Session, _ b: RecoveryPayload.Session) -> [String] {
        func differ<T: Equatable>(_ x: T?, _ y: T?) -> Bool {
            guard let x, let y else { return false }
            return x != y
        }
        var out: [String] = []
        if differ(a.activation.receiverIDUsed, b.activation.receiverIDUsed) { out.append(secretPaths[0]) }
        if differ(a.activation.responseHex, b.activation.responseHex) { out.append(secretPaths[1]) }
        if differ(a.ble.address, b.ble.address) { out.append(secretPaths[2]) }
        if differ(a.ble.pinHex, b.ble.pinHex) { out.append(secretPaths[3]) }
        if differ(a.auth.kAuthHex, b.auth.kAuthHex) { out.append(secretPaths[4]) }
        return out
    }

    /// Equivalencia temporal del historial: mismo hash y tiempos conocidos a ≤ 120 s.
    public static func isEquivalent(_ a: RecoveryPayload.Session, _ b: RecoveryPayload.Session) -> Bool {
        guard a.sensorSerialHash == b.sensorSerialHash,
              let ta = a.activation.activationTimeEpochS, let tb = b.activation.activationTimeEpochS else { return false }
        return abs(ta - tb) <= equivalenceWindowSeconds
    }

    /// `session_id` canónico local para la sesión remota, o `nil` si es desconocida.
    public static func match(_ remote: RecoveryPayload.Session, in state: RecoveryMergeState) -> String? {
        if state.sessions[remote.sessionID] != nil { return remote.sessionID }
        if let canonical = state.aliases[remote.sessionID], state.sessions[canonical] != nil { return canonical }
        for id in state.sessions.keys.sorted() {
            if let local = state.sessions[id], isEquivalent(local, remote) { return id }
        }
        return nil
    }

    /// Aplica todas las sesiones de `payload` sobre `state`.
    public static func apply(_ payload: RecoveryPayload, to state: RecoveryMergeState)
        -> (state: RecoveryMergeState, decisions: [RecoveryMergeDecision]) {
        var state = state
        var decisions: [RecoveryMergeDecision] = []
        for remote in payload.sessions {
            decisions.append(apply(remote, exporter: payload.exportedByAppID, to: &state))
        }
        return (state, decisions)
    }

    /// Aplica una sesión remota.
    public static func apply(_ remote: RecoveryPayload.Session, exporter: String,
                             to state: inout RecoveryMergeState) -> RecoveryMergeDecision {
        guard let id = match(remote, in: state), let local = state.sessions[id] else {
            state.sessions[remote.sessionID] = remote
            state.exporters[remote.sessionID] = exporter
            return .importedNew(sessionID: remote.sessionID)
        }
        if id != remote.sessionID { state.aliases[remote.sessionID] = id }

        if remote.attemptID != local.attemptID {
            let attempt = RecoveryMergeHistoricalAttempt(sessionID: id, session: remote, exporter: exporter)
            guard !state.historical.contains(where: { $0.sessionID == id && $0.session == remote }) else {
                return .duplicateIgnored(sessionID: id)
            }
            state.historical.append(attempt)
            return .historicalAttempt(sessionID: id, attemptID: remote.attemptID)
        }

        let fields = conflictingSecrets(local, remote)
        if !fields.isEmpty {
            guard !state.conflicts.contains(where: { $0.sessionID == id && $0.local == local && $0.remote == remote }) else {
                return .duplicateIgnored(sessionID: id)
            }
            state.conflicts.append(RecoveryMergeConflict(sessionID: id, fields: fields, local: local,
                                                         remote: remote, remoteExporter: exporter))
            return .secretConflict(sessionID: id, fields: fields)
        }

        let localExporter = state.exporters[id]
        let takeRemote: Bool
        if remote.sequence > local.sequence {
            takeRemote = true
        } else if remote.sequence == local.sequence, exporter != localExporter {
            takeRemote = remote.updatedAtUTC > local.updatedAtUTC
        } else {
            takeRemote = false
        }
        guard takeRemote else { return .keptLocal(sessionID: id) }
        state.sessions[id] = remote
        state.exporters[id] = exporter
        return .replacedByRemote(sessionID: id, fromSequence: local.sequence, toSequence: remote.sequence)
    }
}
