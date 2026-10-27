import Foundation

/// Identificador estable de una lectura: `"<session_id>:<analyte>:<life_count>"` (contrato §5.2),
/// `life_count` en decimal sin ceros a la izquierda. No depende del reloj del teléfono.
public struct RecordID: Sendable, Hashable, CustomStringConvertible {
    public let sessionID: String
    public let analyte: Analyte
    public let lifeCount: Int

    public static let lifeCountRange = 0...65_535

    public static func make(sessionID: String, analyte: Analyte = .glucose, lifeCount: Int) -> String {
        sessionID + ":" + analyte.rawValue + ":" + String(lifeCount)
    }

    public var rawValue: String { Self.make(sessionID: sessionID, analyte: analyte, lifeCount: lifeCount) }
    public var description: String { rawValue }

    /// Parser estricto: UUID v4 en minúsculas, analito conocido y `life_count` 0...65535 sin ceros a la izquierda.
    public init?(parsing text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let session = String(parts[0])
        guard Self.isLowercaseUUIDv4(session),
              let analyte = Analyte(rawValue: String(parts[1])) else { return nil }
        let digits = parts[2]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits == "0" || digits.first != "0",
              digits.count <= 5,
              let lc = Int(digits), Self.lifeCountRange.contains(lc) else { return nil }
        self.sessionID = session
        self.analyte = analyte
        self.lifeCount = lc
    }

    /// `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$` (contrato §2).
    public static func isLowercaseUUIDv4(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 36 else { return false }
        for (i, c) in u.enumerated() {
            switch i {
            case 8, 13, 18, 23:
                guard c == 0x2D else { return false }
            case 14:
                guard c == 0x34 else { return false }
            case 19:
                guard c == 0x38 || c == 0x39 || c == 0x61 || c == 0x62 else { return false }
            default:
                guard (0x30...0x39).contains(c) || (0x61...0x66).contains(c) else { return false }
            }
        }
        return true
    }
}
