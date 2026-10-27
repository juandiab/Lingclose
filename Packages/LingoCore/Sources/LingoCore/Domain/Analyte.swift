/// `analyte` (contrato §5.2). v1 solo produce `glucose`.
public enum Analyte: String, Sendable, Codable, Hashable, CaseIterable {
    case glucose
    case ketone
    case lactate
}
