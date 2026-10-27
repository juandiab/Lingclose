import Foundation

/// Lingo CLINICAL_DATA ("fast data", kind 5) after decryption: exactly 14 B.
///
/// `docs/PROTOCOLO_LINGO.md` §6.3 (Juggluco `saveLingoFastData`,
/// `bluetooth.cpp:570-594`):
///
/// | off | size | field |
/// |---|---|---|
/// | 0 | u16 | lifeCount, **bit 15 mandatory**, `& 0x7FFF` |
/// | 2 | 8 | rawData (unused) |
/// | 10 | u16 | current reading (bit 15 invalid, `& 0x0FFF`) |
/// | 12 | u16 | historic reading (same rules) |
///
/// `historicLifeCount = lifeCount < 22 ? 0 : ((lifeCount - 17) / 5) * 5`.
public struct LingoFastData: Equatable, Sendable {
    public static let plaintextSize = 14

    public let raw: Data
    public let lifeCountWord: UInt16
    public let lifeCount: UInt16
    public let rawData: Data
    public let current: LingoReadingWord
    public let historic: LingoReadingWord

    public init(plaintext: Data) throws {
        guard plaintext.count == Self.plaintextSize else {
            throw LingoFastDataError.wrongPlaintextSize(plaintext.count)
        }
        let data = Data(plaintext)
        let word = LingoBytes.u16(data, 0)
        guard word & 0x8000 != 0 else {
            throw LingoFastDataError.missingChannelFlag(lifeCountWord: word)
        }
        self.raw = data
        self.lifeCountWord = word
        self.lifeCount = word & 0x7FFF
        self.rawData = LingoBytes.slice(data, 2, 8)
        self.current = LingoReadingWord(raw: LingoBytes.u16(data, 10))
        self.historic = LingoReadingWord(raw: LingoBytes.u16(data, 12))
    }

    public var historicLifeCount: UInt16 {
        Self.historicLifeCount(forLifeCount: lifeCount)
    }

    public static func historicLifeCount(forLifeCount lifeCount: UInt16) -> UInt16 {
        lifeCount < 22 ? 0 : ((lifeCount - 17) / 5) * 5
    }
}

public enum LingoFastDataError: Error, Equatable, Sendable {
    case wrongPlaintextSize(Int)
    case missingChannelFlag(lifeCountWord: UInt16)
}
