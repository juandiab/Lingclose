import Foundation

public struct LingoHistoricalSample: Equatable, Sendable {
    public let lifeCount: UInt16
    public let word: LingoReadingWord
}

/// Lingo HISTORIC_DATA notification (kind 4) after decryption.
///
/// `docs/PROTOCOLO_LINGO.md` §6.2 (Juggluco `saveLingoHistory`,
/// `bluetooth.cpp:540-568`):
/// - plaintext length 4...14 and even (1...6 values);
/// - word 0 = start; **bit 15 must be set** or the whole notification is
///   rejected; `lifeCount = start & 0x7FFF`;
/// - words 1... = values; `0` terminates the list; bit 15 = invalid;
///   `& 0x0FFF` mg/dL;
/// - value `i` belongs to `lifeCount + 5·i`.
///
/// No 39...501 range check here (policy belongs to the app).
public struct LingoHistoricalPage: Equatable, Sendable {
    public static let minimumPlaintextSize = 4
    public static let maximumPlaintextSize = 14
    public static let sampleSpacingLifeCounts: UInt16 = 5

    public let raw: Data
    public let startWord: UInt16
    public let lifeCount: UInt16
    /// Value words before the first `0` terminator.
    public let values: [LingoReadingWord]

    public init(plaintext: Data) throws {
        let count = plaintext.count
        guard count >= Self.minimumPlaintextSize,
              count <= Self.maximumPlaintextSize,
              count % 2 == 0 else {
            throw LingoHistoricalPageError.wrongPlaintextSize(count)
        }
        let data = Data(plaintext)
        let start = LingoBytes.u16(data, 0)
        guard start & 0x8000 != 0 else {
            throw LingoHistoricalPageError.missingChannelFlag(startWord: start)
        }
        var values: [LingoReadingWord] = []
        for offset in stride(from: 2, to: count, by: 2) {
            let word = LingoBytes.u16(data, offset)
            if word == 0 { break }
            values.append(LingoReadingWord(raw: word))
        }
        self.raw = data
        self.startWord = start
        self.lifeCount = start & 0x7FFF
        self.values = values
    }

    public var samples: [LingoHistoricalSample] {
        values.enumerated().map { index, word in
            LingoHistoricalSample(
                lifeCount: lifeCount + UInt16(index) * Self.sampleSpacingLifeCounts,
                word: word
            )
        }
    }

    /// LifeCount of the last value word (valid or not), `nil` if empty.
    public var lastLifeCount: UInt16? {
        samples.last?.lifeCount
    }
}

public enum LingoHistoricalPageError: Error, Equatable, Sendable {
    case wrongPlaintextSize(Int)
    /// Word 0 without bit 15: Juggluco discards the notification.
    case missingChannelFlag(startWord: UInt16)
}
