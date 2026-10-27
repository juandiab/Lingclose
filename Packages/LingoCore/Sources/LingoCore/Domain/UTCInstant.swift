import Foundation

/// Instante UTC con precisión de segundo. Se codifica como RFC 3339 con sufijo `Z`
/// (`2026-10-27T15:04:05Z`), que es la única forma de fecha que admite el contrato §2.
/// En SQLite se guarda como segundos Unix (`INTEGER`) para que las consultas por rango usen índice.
public struct UTCInstant: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let epochSeconds: Int64

    public init(epochSeconds: Int64) {
        self.epochSeconds = epochSeconds
    }

    /// Trunca hacia abajo al segundo.
    public init(_ date: Date) {
        self.epochSeconds = Int64(date.timeIntervalSince1970.rounded(.down))
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(epochSeconds)) }

    public static func < (lhs: UTCInstant, rhs: UTCInstant) -> Bool { lhs.epochSeconds < rhs.epochSeconds }

    public func adding(seconds: Int64) -> UTCInstant { UTCInstant(epochSeconds: epochSeconds + seconds) }

    /// `YYYY-MM-DDTHH:MM:SSZ`.
    public var rfc3339: String {
        let days = epochSeconds >= 0 ? epochSeconds / 86_400 : (epochSeconds - 86_399) / 86_400
        let secondsOfDay = epochSeconds - days * 86_400
        let (y, m, d) = Self.civil(fromDays: days)
        let hh = secondsOfDay / 3600, mm = (secondsOfDay % 3600) / 60, ss = secondsOfDay % 60
        return Self.pad(y, 4) + "-" + Self.pad(m, 2) + "-" + Self.pad(d, 2) + "T"
            + Self.pad(hh, 2) + ":" + Self.pad(mm, 2) + ":" + Self.pad(ss, 2) + "Z"
    }

    public var description: String { rfc3339 }

    /// Acepta exactamente `YYYY-MM-DDTHH:MM:SSZ` (contrato §2). Devuelve `nil` en cualquier otra forma.
    public init?(rfc3339 text: String) {
        let u = Array(text.utf8)
        guard u.count == 20, u[4] == 0x2D, u[7] == 0x2D, u[10] == 0x54, u[13] == 0x3A, u[16] == 0x3A, u[19] == 0x5A
        else { return nil }
        func num(_ r: Range<Int>) -> Int64? {
            var v: Int64 = 0
            for i in r {
                let c = u[i]
                guard c >= 0x30, c <= 0x39 else { return nil }
                v = v * 10 + Int64(c - 0x30)
            }
            return v
        }
        guard let y = num(0..<4), let mo = num(5..<7), let d = num(8..<10),
              let h = num(11..<13), let mi = num(14..<16), let s = num(17..<19),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 60
        else { return nil }
        let days = Self.days(fromCivil: y, mo, d)
        // Rechaza fechas imposibles como 2026-02-31.
        let back = Self.civil(fromDays: days)
        guard back.0 == y, back.1 == mo, back.2 == d else { return nil }
        self.epochSeconds = days * 86_400 + h * 3600 + mi * 60 + s
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = UTCInstant(rfc3339: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Fecha no RFC 3339 UTC con precisión de segundo")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rfc3339)
    }

    // Algoritmos de Howard Hinnant (days_from_civil / civil_from_days), calendario gregoriano proléptico.
    private static func days(fromCivil y0: Int64, _ m: Int64, _ d: Int64) -> Int64 {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civil(fromDays z0: Int64) -> (Int64, Int64, Int64) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    private static func pad(_ v: Int64, _ width: Int) -> String {
        let s = String(v)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}
