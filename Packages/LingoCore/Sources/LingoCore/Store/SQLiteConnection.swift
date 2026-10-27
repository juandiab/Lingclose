import Foundation
import SQLite3

/// Conexión SQLite sobre la API C del sistema. Solo acepta SQL como `StaticString`: el texto de
/// cada consulta es un literal del código y los datos entran siempre como parámetros ligados.
/// No es `Sendable`: vive dentro del actor `SQLiteStore`, que serializa el acceso.
final class SQLiteConnection {
    private let db: OpaquePointer
    private var cache: [String: SQLiteStatement] = [:]
    private var transactionDepth = 0

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sin memoria"
            if let handle { sqlite3_close_v2(handle) }
            throw SQLiteError(code: rc, message: message)
        }
        self.db = handle
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit {
        cache.removeAll()
        sqlite3_close_v2(db)
    }

    /// Statement preparado y cacheado, ya reiniciado y con los parámetros ligados.
    func prepared(_ sql: StaticString, _ params: [SQLiteValue] = []) throws -> SQLiteStatement {
        let key = sql.description
        let statement: SQLiteStatement
        if let cached = cache[key] {
            statement = cached
        } else {
            statement = try SQLiteStatement(db: db, sql: key)
            cache[key] = statement
        }
        statement.reset()
        try statement.bind(params)
        return statement
    }

    /// Ejecuta un statement que no devuelve filas (o cuyas filas se descartan, como `PRAGMA journal_mode`).
    func run(_ sql: StaticString, _ params: [SQLiteValue] = []) throws {
        let s = try prepared(sql, params)
        defer { s.reset() }
        while try s.step() {}
    }

    /// Ejecuta y mapea cada fila.
    func query<T>(_ sql: StaticString, _ params: [SQLiteValue] = [], _ map: (SQLiteStatement) throws -> T) throws -> [T] {
        let s = try prepared(sql, params)
        defer { s.reset() }
        var out: [T] = []
        while try s.step() { out.append(try map(s)) }
        return out
    }

    func queryFirst<T>(_ sql: StaticString, _ params: [SQLiteValue] = [], _ map: (SQLiteStatement) throws -> T) throws -> T? {
        let s = try prepared(sql, params)
        defer { s.reset() }
        return try s.step() ? map(s) : nil
    }

    /// Guion de varias sentencias (solo migraciones). El texto es un literal estático sin parámetros.
    func executeScript(_ sql: StaticString) throws {
        var message: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql.description, nil, nil, &message)
        guard rc == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(message)
            throw SQLiteError(code: rc, message: text)
        }
    }

    /// Transacción `BEGIN IMMEDIATE`; las anidadas se funden con la exterior.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        if transactionDepth > 0 {
            transactionDepth += 1
            defer { transactionDepth -= 1 }
            return try body()
        }
        try run("BEGIN IMMEDIATE")
        transactionDepth = 1
        do {
            let result = try body()
            transactionDepth = 0
            try run("COMMIT")
            return result
        } catch {
            transactionDepth = 0
            try? run("ROLLBACK")
            throw error
        }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }
    var changes: Int { Int(sqlite3_changes(db)) }
}
