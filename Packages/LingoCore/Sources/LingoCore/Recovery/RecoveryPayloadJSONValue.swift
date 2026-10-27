import Foundation

/// Valor JSON arbitrario. Conserva las claves que la carga útil admite pero LingoScan no interpreta
/// (`additionalProperties: true` en `schemas/recovery_payload.schema.json`), para que un round-trip
/// no pierda nada de lo que escribió otra implementación.
public enum RecoveryJSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([RecoveryJSONValue])
    case object([String: RecoveryJSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .integer(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([RecoveryJSONValue].self) { self = .array(v); return }
        self = .object(try c.decode([String: RecoveryJSONValue].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// Clave dinámica para leer y escribir objetos de la carga útil conservando claves desconocidas.
struct RecoveryCodingKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == RecoveryCodingKey {
    /// Obligatorio no anulable (§3.2): la clave existe y no es `null`.
    func required<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
        try decode(T.self, forKey: RecoveryCodingKey(key))
    }

    /// Hoja anulable: la clave debe existir, su valor puede ser `null`.
    func nullable<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
        let k = RecoveryCodingKey(key)
        guard contains(k) else {
            throw DecodingError.keyNotFound(k, .init(codingPath: codingPath, debugDescription: "falta la clave \(key) (puede ser null, no ausente)"))
        }
        if try decodeNil(forKey: k) { return nil }
        return try decode(T.self, forKey: k)
    }

    /// Claves no interpretadas por LingoScan.
    func extras(excluding known: Set<String>) throws -> [String: RecoveryJSONValue] {
        var out: [String: RecoveryJSONValue] = [:]
        for key in allKeys where !known.contains(key.stringValue) {
            out[key.stringValue] = try decode(RecoveryJSONValue.self, forKey: key)
        }
        return out
    }
}

extension KeyedEncodingContainer where Key == RecoveryCodingKey {
    mutating func put<T: Encodable>(_ value: T, _ key: String) throws {
        try encode(value, forKey: RecoveryCodingKey(key))
    }

    /// Escribe `null` explícito: las hojas anulables existen siempre como clave.
    mutating func putNullable<T: Encodable>(_ value: T?, _ key: String) throws {
        if let value { try encode(value, forKey: RecoveryCodingKey(key)) } else { try encodeNil(forKey: RecoveryCodingKey(key)) }
    }

    mutating func putExtras(_ extras: [String: RecoveryJSONValue], excluding known: Set<String>) throws {
        for (key, value) in extras where !known.contains(key) {
            try encode(value, forKey: RecoveryCodingKey(key))
        }
    }
}
