/// Agregado de un grupo de eventos (franja horaria, tramo de carbohidratos, de duración…).
public struct ReportGroup<Key: Sendable & Hashable & Codable, Stats: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    public let key: Key
    public let stats: Stats

    public init(key: Key, stats: Stats) {
        self.key = key
        self.stats = stats
    }
}
