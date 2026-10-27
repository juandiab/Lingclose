/// `eligibility.status` (contrato §5.2).
public enum EligibilityStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case eligible
    case excluded
}
