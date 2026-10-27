/// Conflicto auditado (`conflicts.ndjson`, contrato §5.5). Se conserva; no se importa.
public struct ConflictRecord: Sendable, Hashable, Codable {
    public var at: UTCInstant
    public var kind: ConflictKind
    /// `record_id`, `event_id` o `session_id` según `kind`.
    public var id: String
    public var resolution: ConflictResolution
    public var local: JSONValue?
    public var remote: JSONValue?
    /// Obligatorio (UUID) cuando `resolution == .divergent` y el remoto vino de un paquete.
    public var remoteArchiveID: String?

    public init(
        at: UTCInstant,
        kind: ConflictKind,
        id: String,
        resolution: ConflictResolution,
        local: JSONValue? = nil,
        remote: JSONValue? = nil,
        remoteArchiveID: String? = nil
    ) {
        self.at = at
        self.kind = kind
        self.id = id
        self.resolution = resolution
        self.local = local
        self.remote = remote
        self.remoteArchiveID = remoteArchiveID
    }

    enum CodingKeys: String, CodingKey {
        case at = "at_utc"
        case kind, id, resolution, local, remote
        case remoteArchiveID = "remote_archive_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(at, forKey: .at)
        try c.encode(kind, forKey: .kind)
        try c.encode(id, forKey: .id)
        try c.encode(resolution, forKey: .resolution)
        try c.encodeIfPresent(local, forKey: .local)
        try c.encodeIfPresent(remote, forKey: .remote)
        try c.encode(remoteArchiveID, forKey: .remoteArchiveID)
    }
}
