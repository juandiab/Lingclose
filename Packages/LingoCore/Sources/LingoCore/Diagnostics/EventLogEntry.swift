/// Entrada de `event_log` (siempre redactada; ver `LogMessage` y `Redactor`).
public struct EventLogEntry: Sendable, Hashable {
    public let id: Int64
    public let at: UTCInstant
    public let level: EventLogLevel
    public let category: String
    public let message: String

    public init(id: Int64, at: UTCInstant, level: EventLogLevel, category: String, message: String) {
        self.id = id
        self.at = at
        self.level = level
        self.category = category
        self.message = message
    }
}
