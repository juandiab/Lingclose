import Foundation

/// Comprobaciones léxicas de `schemas/recovery_payload.schema.json` (`$defs`), sin expresiones regulares.
enum RecoveryFormat {
    static func check(_ ok: Bool, _ path: String, _ reason: String) throws {
        guard ok else { throw RecoveryPayloadError.invalid(path: path, reason: reason) }
    }

    static func optional(_ value: String?, _ path: String, _ test: (String) -> Bool) throws {
        if let value { try check(test(value), path, "formato") }
    }

    private static func isLowerHexDigit(_ c: UInt8) -> Bool { (0x30...0x39).contains(c) || (0x61...0x66).contains(c) }
    private static func isUpperHexDigit(_ c: UInt8) -> Bool { (0x30...0x39).contains(c) || (0x41...0x46).contains(c) }
    private static func isDigit(_ c: UInt8) -> Bool { (0x30...0x39).contains(c) }

    /// Hex en minúsculas de longitud par; con `bytes`, exactamente esa longitud.
    static func isHex(_ s: String, bytes: Int? = nil) -> Bool {
        let u = Array(s.utf8)
        guard u.count.isMultiple(of: 2), u.allSatisfy(isLowerHexDigit) else { return false }
        if let bytes { return u.count == bytes * 2 }
        return true
    }

    static func isSHA256(_ s: String) -> Bool { isHex(s, bytes: 32) }

    /// `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`
    static func isUUIDv4(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 36 else { return false }
        for (i, c) in u.enumerated() {
            switch i {
            case 8, 13, 18, 23: guard c == UInt8(ascii: "-") else { return false }
            case 14: guard c == UInt8(ascii: "4") else { return false }
            case 19: guard "89ab".utf8.contains(c) else { return false }
            default: guard isLowerHexDigit(c) else { return false }
            }
        }
        return true
    }

    /// `^([0-9A-F]{2}:){5}[0-9A-F]{2}$`
    static func isMACAddress(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 17 else { return false }
        for (i, c) in u.enumerated() {
            if i % 3 == 2 { guard c == UInt8(ascii: ":") else { return false } }
            else { guard isUpperHexDigit(c) else { return false } }
        }
        return true
    }

    /// `YYYY-MM-DDTHH:MM:SSZ` con los rangos del esquema.
    static func isDateTimeUTC(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 20, u[4] == UInt8(ascii: "-"), u[7] == UInt8(ascii: "-"), u[10] == UInt8(ascii: "T"),
              u[13] == UInt8(ascii: ":"), u[16] == UInt8(ascii: ":"), u[19] == UInt8(ascii: "Z") else { return false }
        for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] where !isDigit(u[i]) { return false }
        func num(_ a: Int, _ b: Int) -> Int { Int(u[a] - 0x30) * 10 + Int(u[b] - 0x30) }
        let month = num(5, 6), day = num(8, 9), hour = num(11, 12), minute = num(14, 15), second = num(17, 18)
        return (1...12).contains(month) && (1...31).contains(day) && hour <= 23 && minute <= 59 && second <= 59
    }

    /// Instante UTC con precisión de segundo, como lo exige el esquema.
    static func utcString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

extension RecoveryPayload {
    /// `YYYY-MM-DDTHH:MM:SSZ` (UTC, segundos) para `exported_at_utc`, `updated_at_utc` y similares.
    public static func utcString(_ date: Date) -> String { RecoveryFormat.utcString(date) }

    /// Inverso de `utcString`; `nil` si no cumple el formato.
    public static func date(fromUTC string: String) -> Date? {
        guard RecoveryFormat.isDateTimeUTC(string) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
