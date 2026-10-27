/// Implementación que produjo `raw` (`decoder`, contrato §5.2).
public struct DecoderInfo: Sendable, Hashable, Codable {
    public var id: String
    public var version: String

    public init(id: String, version: String) {
        self.id = id
        self.version = version
    }

    /// Decodificador de LingoScan (manifest de ejemplo del contrato §4).
    public static let lingoScan = DecoderInfo(id: "lingoscan-claude-lingo", version: "1.0.0")
}
