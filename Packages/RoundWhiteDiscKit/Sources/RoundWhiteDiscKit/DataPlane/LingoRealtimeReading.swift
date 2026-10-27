import Foundation

/// Analyte type codes from the Lingo realtime type map (byte 34).
/// `docs/PROTOCOLO_LINGO.md` §3.1 (`lingo_realtime.h:55-60`).
public enum LingoAnalyteType: Equatable, Sendable {
    case inactive
    case glucose
    case ketone
    case lactate
    case unknown(UInt8)

    public init(code: UInt8) {
        switch code {
        case 0: self = .inactive
        case 1: self = .glucose
        case 2: self = .ketone
        case 3: self = .lactate
        default: self = .unknown(code)
        }
    }

    public var code: UInt8 {
        switch self {
        case .inactive: return 0
        case .glucose: return 1
        case .ketone: return 2
        case .lactate: return 3
        case .unknown(let code): return code
        }
    }
}

/// One 15-byte analyte block of the Lingo realtime frame.
/// Offsets relative to the block start (`docs/PROTOCOLO_LINGO.md` §3.2,
/// `lingo_realtime.c:55-63`).
///
/// | rel | size | field |
/// |---|---|---|
/// | 0 | u16 | capped (bit 15 invalid, `& 0x0FFF`) |
/// | 2 | s16 | rate of change, 0.01 mg/dL/min; `-32768` unknown |
/// | 4 | u16 | extended code (unused) |
/// | 6 | u16 | projected (unused) |
/// | 8 | u16 | historic capped |
/// | 10 | u8 | trend `& 0x07` (6, 7 → 0); bit 3 actionable |
/// | 11 | u16 | uncapped |
/// | 13 | u16 | historic uncapped |
public struct LingoAnalyteBlock: Equatable, Sendable {
    public static let size = 15
    public static let unknownRate: Int16 = .min

    public let raw: Data
    public let cappedRaw: UInt16
    public let rateCentiRaw: Int16
    public let extendedCode: UInt16
    public let projected: UInt16
    public let historicCappedRaw: UInt16
    public let trendByte: UInt8
    public let uncappedRaw: UInt16
    public let historicUncappedRaw: UInt16

    init(block: Data) {
        precondition(block.count == Self.size)
        self.raw = Data(block)
        self.cappedRaw = LingoBytes.u16(block, 0)
        self.rateCentiRaw = LingoBytes.s16(block, 2)
        self.extendedCode = LingoBytes.u16(block, 4)
        self.projected = LingoBytes.u16(block, 6)
        self.historicCappedRaw = LingoBytes.u16(block, 8)
        self.trendByte = LingoBytes.byte(block, 10)
        self.uncappedRaw = LingoBytes.u16(block, 11)
        self.historicUncappedRaw = LingoBytes.u16(block, 13)
    }

    public var capped: LingoReadingWord { LingoReadingWord(raw: cappedRaw) }
    public var historicCapped: LingoReadingWord { LingoReadingWord(raw: historicCappedRaw) }
    public var uncapped: LingoReadingWord { LingoReadingWord(raw: uncappedRaw) }
    public var historicUncapped: LingoReadingWord { LingoReadingWord(raw: historicUncappedRaw) }

    /// Rate in 0.01 mg/dL/min, `nil` when the sensor reports `-32768`.
    public var rateCenti: Int16? {
        rateCentiRaw == Self.unknownRate ? nil : rateCentiRaw
    }

    /// `trendByte & 0x07`; reserved values 6 and 7 map to 0 (unknown).
    /// 0 unknown, 1 falling fast, 2 falling, 3 stable, 4 rising, 5 rising fast.
    public var trend: UInt8 {
        let value = trendByte & 0x07
        return value > 5 ? 0 : value
    }

    /// Bit 3 of the trend byte.
    public var actionable: Bool {
        trendByte & 0x08 != 0
    }
}

/// Lingo realtime frame: plaintext of exactly 51 bytes (GLUCOSE_DATA, kind 3).
///
/// `docs/PROTOCOLO_LINGO.md` §3 (Juggluco 11.5.4 `lingo_parse_realtime`,
/// `lingo_realtime.c:73-140`):
///
/// | off | size | field |
/// |---|---|---|
/// | 0 | u16 | lifeCount |
/// | 2 | u16 | historicLifeCount |
/// | 4 | 15 | analyte block channel 0 |
/// | 19 | 15 | analyte block channel 1 |
/// | 34 | u8 | type map (low nibble ch0, high nibble ch1) |
/// | 35 | 16 | reserved (uninterpreted; contains temperature @37) |
/// | 37 | u16 | temperature, centi-°C unsigned; `0x8000` invalid |
///
/// Glucose is taken from the **first** channel whose type is glucose; no
/// channel is assumed. Values with the quality flag are exposed raw and never
/// converted into a number. No eligibility or display policy is applied.
public struct LingoRealtimeReading: Equatable, Sendable {
    public static let plaintextSize = 51
    public static let typeMapOffset = 34
    public static let reservedRange = 35..<51
    public static let temperatureOffset = 37
    public static let invalidTemperature: UInt16 = 0x8000

    public let raw: Data
    public let lifeCount: UInt16
    public let historicLifeCount: UInt16
    /// Both analyte blocks, index = channel (0, 1).
    public let blocks: [LingoAnalyteBlock]
    public let typeMapByte: UInt8
    /// Types per channel, index = channel (0, 1).
    public let analyteTypes: [LingoAnalyteType]
    /// Bytes 35...50 (16 B), uninterpreted. Includes the temperature word.
    public let reserved: Data
    public let temperatureRaw: UInt16
    /// Index of the first glucose channel, `nil` if none.
    public let channel: Int?

    public init(plaintext: Data) throws {
        guard plaintext.count == Self.plaintextSize else {
            throw LingoRealtimeReadingError.wrongPlaintextSize(plaintext.count)
        }
        let data = Data(plaintext)
        self.raw = data
        self.lifeCount = LingoBytes.u16(data, 0)
        self.historicLifeCount = LingoBytes.u16(data, 2)
        self.blocks = [
            LingoAnalyteBlock(block: LingoBytes.slice(data, 4, LingoAnalyteBlock.size)),
            LingoAnalyteBlock(block: LingoBytes.slice(data, 19, LingoAnalyteBlock.size)),
        ]
        let typeMap = LingoBytes.byte(data, Self.typeMapOffset)
        self.typeMapByte = typeMap
        let types = [LingoAnalyteType(code: typeMap & 0x0F), LingoAnalyteType(code: typeMap >> 4)]
        self.analyteTypes = types
        self.reserved = LingoBytes.slice(data, Self.reservedRange.lowerBound, Self.reservedRange.count)
        self.temperatureRaw = LingoBytes.u16(data, Self.temperatureOffset)
        self.channel = types.firstIndex(of: .glucose)
    }

    public static func parse(_ plaintext: Data) throws -> LingoRealtimeReading {
        try LingoRealtimeReading(plaintext: plaintext)
    }

    /// Analyte block of the selected glucose channel.
    public var glucose: LingoAnalyteBlock? {
        channel.map { blocks[$0] }
    }

    public var hasGlucoseChannel: Bool {
        channel != nil
    }

    /// Raw capped word of the glucose channel.
    public var cappedRaw: UInt16? {
        glucose?.cappedRaw
    }

    /// `(cappedRaw & 0x6000) >> 13` of the glucose channel.
    public var rangeBits: UInt8? {
        glucose?.capped.rangeBits
    }

    /// Bit 15 of the glucose channel's capped word. `nil` without a glucose channel.
    public var qualityFlag: Bool? {
        glucose?.capped.qualityFlag
    }

    /// Juggluco's `glucose_valid`: a glucose channel exists and its capped word has no quality flag.
    public var isGlucoseValid: Bool {
        qualityFlag == false
    }

    /// Capped glucose, mg/dL. `nil` when flagged or without a glucose channel.
    public var cappedMgDL: UInt16? {
        glucose?.capped.mgDL
    }

    /// Uncapped glucose (what Juggluco stores), mg/dL. `nil` when flagged.
    public var uncappedMgDL: UInt16? {
        glucose?.uncapped.mgDL
    }

    public var historicCappedMgDL: UInt16? {
        glucose?.historicCapped.mgDL
    }

    public var historicUncappedMgDL: UInt16? {
        glucose?.historicUncapped.mgDL
    }

    /// Raw rate (0.01 mg/dL/min). `-32768` when unknown or without a glucose channel.
    public var rateCentiRaw: Int16 {
        glucose?.rateCentiRaw ?? LingoAnalyteBlock.unknownRate
    }

    public var rateCenti: Int16? {
        glucose?.rateCenti
    }

    /// Trend 0...5; 0 when unknown or without a glucose channel.
    public var trend: UInt8 {
        glucose?.trend ?? 0
    }

    public var actionable: Bool {
        glucose?.actionable ?? false
    }

    public var isTemperatureValid: Bool {
        temperatureRaw != Self.invalidTemperature
    }

    /// Temperature in centi-°C (unsigned), `nil` when `0x8000`.
    public var temperatureCentiCelsius: UInt16? {
        isTemperatureValid ? temperatureRaw : nil
    }
}

public enum LingoRealtimeReadingError: Error, Equatable, Sendable {
    case wrongPlaintextSize(Int)
}
