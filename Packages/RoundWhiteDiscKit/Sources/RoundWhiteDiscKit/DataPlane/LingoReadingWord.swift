import Foundation

/// One 16-bit Lingo glucose word (realtime, historical page or fast data).
///
/// Layout (`docs/PROTOCOLO_LINGO.md` §3.2, §3.3, §6.2, §6.3; Juggluco
/// `lingo_realtime.c:65-66, 103-126`):
/// - bit 15: data-quality flag. When set the word is invalid and **must never
///   be turned into a number**; `mgDL` is `nil`.
/// - bits 13-14: "result range" (0...3). Meaning not determined.
/// - bit 12: discarded by the `0x0FFF` mask, no known semantics.
/// - bits 0-11: value in mg/dL (scale 1).
///
/// No display-range clamp (39...501 or similar) is applied here: that is an
/// app policy decision (LingoCore), not a protocol rule.
public struct LingoReadingWord: Equatable, Sendable {
    public static let qualityFlagMask: UInt16 = 0x8000
    public static let rangeMask: UInt16 = 0x6000
    public static let valueMask: UInt16 = 0x0FFF

    public let raw: UInt16

    public init(raw: UInt16) {
        self.raw = raw
    }

    /// Bit 15. `true` means invalid (warm-up, sensor error, ...).
    public var qualityFlag: Bool {
        raw & Self.qualityFlagMask != 0
    }

    public var isValid: Bool {
        !qualityFlag
    }

    /// `raw & 0x0FFF` when bit 15 is clear; `nil` otherwise.
    public var mgDL: UInt16? {
        qualityFlag ? nil : raw & Self.valueMask
    }

    /// `(raw & 0x6000) >> 13`, exposed raw.
    public var rangeBits: UInt8 {
        UInt8((raw & Self.rangeMask) >> 13)
    }

    /// Bit 12, exposed raw (no documented meaning).
    public var bit12: Bool {
        raw & 0x1000 != 0
    }
}

enum LingoBytes {
    static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
    }

    static func s16(_ data: Data, _ offset: Int) -> Int16 {
        Int16(bitPattern: u16(data, offset))
    }

    static func byte(_ data: Data, _ offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    static func slice(_ data: Data, _ offset: Int, _ length: Int) -> Data {
        let start = data.startIndex + offset
        return Data(data[start..<(start + length)])
    }
}
