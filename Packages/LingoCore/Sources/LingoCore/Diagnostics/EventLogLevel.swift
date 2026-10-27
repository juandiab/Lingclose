/// Nivel de una entrada de `event_log`.
public enum EventLogLevel: String, Sendable, Codable, Hashable, CaseIterable {
    case debug
    case info
    case warning
    case error
}
