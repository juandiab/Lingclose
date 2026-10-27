/// Evento del diario (comida, ejercicio, nota) según el contrato §5.3.
public struct DiaryEvent: Sendable, Hashable, Codable {
    public var eventID: String
    public var kind: DiaryEventKind
    public var at: UTCInstant
    public var tz: String
    public var durationMin: Int?
    public var carbsG: Double?
    public var text: String?
    public var createdAt: UTCInstant
    public var updatedAt: UTCInstant
    /// Contador local informativo; no se compara entre apps (C3).
    public var revision: Int
    /// Identidad de esta edición. Cada guardado genera uno nuevo.
    public var editID: String
    /// Edición sobre la que se hizo esta; `nil` en la creación.
    public var parentEditID: String?
    public var editedByAppID: String
    public var deleted: Bool
    public var synthetic: Bool
    public var importedFrom: ImportedFrom?

    public init(
        eventID: String,
        kind: DiaryEventKind,
        at: UTCInstant,
        tz: String,
        durationMin: Int? = nil,
        carbsG: Double? = nil,
        text: String? = nil,
        createdAt: UTCInstant,
        updatedAt: UTCInstant,
        revision: Int = 1,
        editID: String,
        parentEditID: String? = nil,
        editedByAppID: String,
        deleted: Bool = false,
        synthetic: Bool,
        importedFrom: ImportedFrom? = nil
    ) {
        self.eventID = eventID
        self.kind = kind
        self.at = at
        self.tz = tz
        self.durationMin = durationMin
        self.carbsG = carbsG
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.editID = editID
        self.parentEditID = parentEditID
        self.editedByAppID = editedByAppID
        self.deleted = deleted
        self.synthetic = synthetic
        self.importedFrom = importedFrom
    }

    /// Eslabón de linaje de esta versión.
    public var editLink: EditLink { EditLink(editID: editID, parentEditID: parentEditID) }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case kind
        case at = "at_utc"
        case tz
        case durationMin = "duration_min"
        case carbsG = "carbs_g"
        case text
        case createdAt = "created_at_utc"
        case updatedAt = "updated_at_utc"
        case revision
        case editID = "edit_id"
        case parentEditID = "parent_edit_id"
        case editedByAppID = "edited_by_app_id"
        case deleted, synthetic
        case importedFrom = "imported_from"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(kind, forKey: .kind)
        try c.encode(at, forKey: .at)
        try c.encode(tz, forKey: .tz)
        try c.encode(durationMin, forKey: .durationMin)
        try c.encode(carbsG, forKey: .carbsG)
        try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(revision, forKey: .revision)
        try c.encode(editID, forKey: .editID)
        try c.encode(parentEditID, forKey: .parentEditID)
        try c.encode(editedByAppID, forKey: .editedByAppID)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(synthetic, forKey: .synthetic)
        try c.encode(importedFrom, forKey: .importedFrom)
    }
}
