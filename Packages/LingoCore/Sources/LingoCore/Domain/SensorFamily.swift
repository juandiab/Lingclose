/// Familia del sensor según el contrato §5.1 (`sensor_family`).
/// Propio de LingoCore: no depende del `SensorFamily` del fork de RoundWhiteDiscKit.
public enum SensorFamily: String, Sendable, Codable, Hashable, CaseIterable {
    case lingo
    case libre3
    case unknown
}
