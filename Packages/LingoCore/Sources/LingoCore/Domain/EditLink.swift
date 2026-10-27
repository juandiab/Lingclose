/// Eslabón del linaje de ediciones `edit_id → parent_edit_id` (contrato §5.3, `edit_ancestors`).
public struct EditLink: Sendable, Hashable, Codable {
    public var editID: String
    public var parentEditID: String?

    public init(editID: String, parentEditID: String?) {
        self.editID = editID
        self.parentEditID = parentEditID
    }

    enum CodingKeys: String, CodingKey {
        case editID = "edit_id"
        case parentEditID = "parent_edit_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(editID, forKey: .editID)
        try c.encode(parentEditID, forKey: .parentEditID)
    }
}
