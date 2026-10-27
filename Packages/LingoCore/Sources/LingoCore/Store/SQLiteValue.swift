import Foundation

/// Valor que se liga a un parámetro `?` de un statement preparado. Nunca se interpola en el SQL.
public enum SQLiteValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public init(_ value: Int?) { self = value.map { .integer(Int64($0)) } ?? .null }
    public init(_ value: Int64?) { self = value.map { .integer($0) } ?? .null }
    public init(_ value: Bool?) { self = value.map { .integer($0 ? 1 : 0) } ?? .null }
    public init(_ value: Double?) { self = value.map { .real($0) } ?? .null }
    public init(_ value: String?) { self = value.map { .text($0) } ?? .null }
    public init(_ value: Data?) { self = value.map { .blob($0) } ?? .null }
}
