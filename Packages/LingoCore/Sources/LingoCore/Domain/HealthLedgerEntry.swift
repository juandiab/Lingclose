/// Un intento de escritura en Health (`health_export_ledger.ndjson`, contrato §5.4). Append-only.
public struct HealthLedgerEntry: Sendable, Hashable, Codable {
    public var attemptID: String
    /// `record_id` (glucosa) o `event_id` (carbohidratos).
    public var subjectID: String
    public var subjectKind: HealthSubjectKind
    public var writerAppID: String
    public var syncIdentifier: String
    public var syncVersion: Int
    public var exportedAt: UTCInstant
    public var result: HealthLedgerResult

    public init(
        attemptID: String,
        subjectID: String,
        subjectKind: HealthSubjectKind,
        writerAppID: String,
        syncIdentifier: String,
        syncVersion: Int,
        exportedAt: UTCInstant,
        result: HealthLedgerResult
    ) {
        self.attemptID = attemptID
        self.subjectID = subjectID
        self.subjectKind = subjectKind
        self.writerAppID = writerAppID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.exportedAt = exportedAt
        self.result = result
    }

    enum CodingKeys: String, CodingKey {
        case attemptID = "attempt_id"
        case subjectID = "subject_id"
        case subjectKind = "subject_kind"
        case writerAppID = "writer_app_id"
        case syncIdentifier = "sync_identifier"
        case syncVersion = "sync_version"
        case exportedAt = "exported_at_utc"
        case result
    }
}
