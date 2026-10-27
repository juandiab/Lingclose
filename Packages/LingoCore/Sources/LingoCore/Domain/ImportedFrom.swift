/// Procedencia de un registro importado (`imported_from`, contrato §5.1–§5.3).
public struct ImportedFrom: Sendable, Hashable, Codable {
    public var appID: String
    public var archiveID: String

    public init(appID: String, archiveID: String) {
        self.appID = appID
        self.archiveID = archiveID
    }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case archiveID = "archive_id"
    }
}
