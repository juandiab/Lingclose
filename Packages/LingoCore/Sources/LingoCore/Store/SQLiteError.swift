/// Error de la API C de SQLite, con el código y el mensaje de `sqlite3_errmsg`.
public struct SQLiteError: Error, Sendable, Hashable, CustomStringConvertible {
    public let code: Int32
    public let message: String

    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "SQLite \(code): \(message)" }
}
