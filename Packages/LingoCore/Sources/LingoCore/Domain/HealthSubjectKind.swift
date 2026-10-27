/// `subject_kind` del ledger (contrato §5.4).
public enum HealthSubjectKind: String, Sendable, Codable, Hashable, CaseIterable {
    case glucose
    case carbs
}
