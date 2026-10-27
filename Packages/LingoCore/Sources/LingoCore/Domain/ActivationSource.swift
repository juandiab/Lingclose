/// `activation_source` (contrato §5.1), relativo al productor.
public enum ActivationSource: String, Sendable, Codable, Hashable, CaseIterable {
    case thisApp = "this_app"
    case imported
    case unknown
}
