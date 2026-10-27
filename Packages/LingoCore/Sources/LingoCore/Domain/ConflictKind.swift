/// `kind` de un conflicto (contrato §5.5).
public enum ConflictKind: String, Sendable, Codable, Hashable, CaseIterable {
    case reading
    case event
    case session
}
