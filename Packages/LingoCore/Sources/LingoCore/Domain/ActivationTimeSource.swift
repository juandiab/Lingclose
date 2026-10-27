/// `activation_time_source` (contrato §5.1).
public enum ActivationTimeSource: String, Sendable, Codable, Hashable, CaseIterable {
    case nfcResponse = "nfc_response"
    case command
    case imported
}
