import Foundation

/// Mensaje de `event_log` que solo admite interpolaciones redactadas o de tipos inocuos.
///
/// ```swift
/// "Trama \(hex: frame) del sensor \(serial: serial), lc \(lifeCount)"
/// ```
/// No existe una interpolación genérica de `String`/`Data`: para texto libre se usa `\(public:)`,
/// que obliga a quien escribe a declarar que el valor no es sensible.
public struct LogMessage: Sendable, Hashable, ExpressibleByStringInterpolation, CustomStringConvertible {
    public let text: String
    public var description: String { text }

    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: Interpolation) { text = stringInterpolation.text }

    public struct Interpolation: StringInterpolationProtocol {
        var text = ""
        public init(literalCapacity: Int, interpolationCount: Int) { text.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { text += literal }
        public mutating func appendInterpolation(hex data: Data) { text += Redactor.hex(data) }
        public mutating func appendInterpolation(serial: String) { text += Redactor.serial(serial) }
        public mutating func appendInterpolation(secret data: Data) { text += Redactor.secret(data) }
        public mutating func appendInterpolation<I: BinaryInteger>(_ value: I) { text += String(value) }
        public mutating func appendInterpolation(_ value: Bool) { text += value ? "true" : "false" }
        public mutating func appendInterpolation(_ value: UTCInstant) { text += value.rfc3339 }
        /// Texto que quien llama declara no sensible (estados, fases, códigos de error).
        public mutating func appendInterpolation(public value: String) { text += value }
    }
}
