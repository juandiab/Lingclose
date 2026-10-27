/// Hueco pendiente: sujeto elegible, no borrado y no sintético sin estado `written` para ninguna escritora (§5.4).
/// Para comidas, `written` cuenta solo si cubre la `revision` actual del evento (`revision`).
public struct PendingHealthSubject: Sendable, Hashable {
    public let subjectID: String
    public let subjectKind: HealthSubjectKind
    public let measuredAt: UTCInstant
    /// `revision` actual del evento (comidas); `nil` para glucosa. Un `written` de una versión menor no basta.
    public let revision: Int?

    public init(subjectID: String, subjectKind: HealthSubjectKind, measuredAt: UTCInstant, revision: Int? = nil) {
        self.subjectID = subjectID
        self.subjectKind = subjectKind
        self.measuredAt = measuredAt
        self.revision = revision
    }
}
