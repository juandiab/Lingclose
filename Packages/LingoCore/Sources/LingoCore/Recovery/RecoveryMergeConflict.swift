/// Conflicto de secretos (§5 paso 4, draft.4): mismo `attempt_id` y algún secreto no nulo distinto.
/// Se conservan íntegras ambas copias; nunca se mezclan campos ni decide `sequence` o el reloj.
public struct RecoveryMergeConflict: Sendable, Hashable, Codable, CustomStringConvertible {
    /// `session_id` canónico local.
    public let sessionID: String
    /// Rutas de secreto que difieren (`ble.pin_hex`, …), nunca sus valores.
    public let fields: [String]
    public let local: RecoveryPayload.Session
    public let remote: RecoveryPayload.Session
    public let remoteExporter: String

    public init(sessionID: String, fields: [String], local: RecoveryPayload.Session,
                remote: RecoveryPayload.Session, remoteExporter: String) {
        self.sessionID = sessionID
        self.fields = fields
        self.local = local
        self.remote = remote
        self.remoteExporter = remoteExporter
    }

    public var description: String {
        "RecoveryMergeConflict(\(sessionID), \(fields.joined(separator: ",")), local seq \(local.sequence), remota seq \(remote.sequence))"
    }
}
