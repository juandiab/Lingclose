/// Qué hizo la fusión con una sesión remota (§5 paso 4). Solo identificadores, sin secretos.
public enum RecoveryMergeDecision: Sendable, Hashable {
    /// Sesión desconocida localmente: se importa entera.
    case importedNew(sessionID: String)
    /// Mismo intento, copia remota posterior sin conflicto: se toma entera.
    case replacedByRemote(sessionID: String, fromSequence: Int, toSequence: Int)
    /// Mismo intento, copia remota anterior o igual (o desempate a favor de la local).
    case keptLocal(sessionID: String)
    /// Conflicto de secretos: la local queda intacta, ambas copias se conservan.
    case secretConflict(sessionID: String, fields: [String])
    /// `attempt_id` distinto: intento histórico.
    case historicalAttempt(sessionID: String, attemptID: String)
    /// Repetición idéntica de un conflicto o histórico ya registrado (importación idempotente).
    case duplicateIgnored(sessionID: String)

    public var sessionID: String {
        switch self {
        case .importedNew(let id), .keptLocal(let id), .duplicateIgnored(let id): id
        case .replacedByRemote(let id, _, _), .secretConflict(let id, _), .historicalAttempt(let id, _): id
        }
    }
}
