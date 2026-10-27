/// Otro `session_id` con el que se conoce la misma sesión física (contrato §5.1, C1).
public struct SessionAlias: Sendable, Hashable, Codable {
    public var sessionID: String
    public var appID: String
    public var archiveID: String
    public var recordedAt: UTCInstant

    public init(sessionID: String, appID: String, archiveID: String, recordedAt: UTCInstant) {
        self.sessionID = sessionID
        self.appID = appID
        self.archiveID = archiveID
        self.recordedAt = recordedAt
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case appID = "app_id"
        case archiveID = "archive_id"
        case recordedAt = "recorded_at_utc"
    }
}
