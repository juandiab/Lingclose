/// `end_reason` (contrato §5.1).
public enum SessionEndReason: String, Sendable, Codable, Hashable, CaseIterable {
    case expired
    case terminated
    case replaced
    case unknown
}
