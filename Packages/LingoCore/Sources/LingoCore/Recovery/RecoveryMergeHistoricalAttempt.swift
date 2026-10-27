/// Otro intento de activación (`attempt_id` distinto) de la misma sesión física. Se guarda como histórico;
/// nunca reemplaza al activo, nunca reactiva ni cambia el receptor.
public struct RecoveryMergeHistoricalAttempt: Sendable, Hashable, Codable {
    public let sessionID: String
    public let session: RecoveryPayload.Session
    public let exporter: String

    public init(sessionID: String, session: RecoveryPayload.Session, exporter: String) {
        self.sessionID = sessionID
        self.session = session
        self.exporter = exporter
    }
}
