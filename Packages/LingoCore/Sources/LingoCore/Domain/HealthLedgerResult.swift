/// `result` de un intento de escritura en Health (contrato §5.4).
public enum HealthLedgerResult: String, Sendable, Codable, Hashable, CaseIterable {
    case written
    case failed
    case unknown
}
