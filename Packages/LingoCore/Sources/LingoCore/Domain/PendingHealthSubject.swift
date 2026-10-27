/// Hueco pendiente: sujeto elegible, no borrado y no sintético sin estado `written` para ninguna escritora (§5.4).
public struct PendingHealthSubject: Sendable, Hashable {
    public let subjectID: String
    public let subjectKind: HealthSubjectKind
    public let measuredAt: UTCInstant

    public init(subjectID: String, subjectKind: HealthSubjectKind, measuredAt: UTCInstant) {
        self.subjectID = subjectID
        self.subjectKind = subjectKind
        self.measuredAt = measuredAt
    }
}
