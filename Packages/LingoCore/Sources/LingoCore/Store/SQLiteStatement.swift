import Foundation
import SQLite3

/// Statement preparado. Lo crea y lo cachea `SQLiteConnection`; vive dentro del actor `SQLiteStore`.
final class SQLiteStatement {
    private let handle: OpaquePointer
    private let db: OpaquePointer

    /// `SQLITE_TRANSIENT`: SQLite copia el buffer antes de que `bind` regrese.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(db: OpaquePointer, sql: String) throws {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v3(db, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
        self.handle = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(handle) }

    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func bind(_ values: [SQLiteValue]) throws {
        let expected = Int(sqlite3_bind_parameter_count(handle))
        guard expected == values.count else {
            throw SQLiteError(code: SQLITE_RANGE, message: "Se esperaban \(expected) parámetros y llegaron \(values.count)")
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .null: rc = sqlite3_bind_null(handle, index)
            case .integer(let v): rc = sqlite3_bind_int64(handle, index, v)
            case .real(let v): rc = sqlite3_bind_double(handle, index, v)
            case .text(let v): rc = sqlite3_bind_text(handle, index, v, -1, Self.transient)
            case .blob(let v):
                rc = v.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(handle, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                }
            }
            guard rc == SQLITE_OK else { throw error(rc) }
        }
    }

    /// `true` si hay fila; `false` al terminar.
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw error(rc)
        }
    }

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }

    func int64(_ column: Int32) -> Int64? {
        isNull(column) ? nil : sqlite3_column_int64(handle, column)
    }

    func int(_ column: Int32) -> Int? { int64(column).map { Int($0) } }

    func bool(_ column: Int32) -> Bool? { int64(column).map { $0 != 0 } }

    func double(_ column: Int32) -> Double? {
        isNull(column) ? nil : sqlite3_column_double(handle, column)
    }

    func text(_ column: Int32) -> String? {
        guard let p = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: p)
    }

    private func error(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db)))
    }
}
