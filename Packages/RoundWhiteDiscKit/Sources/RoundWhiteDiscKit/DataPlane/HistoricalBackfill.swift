import Foundation

public struct HistoricalBackfillGap: Equatable, Sendable {
    public let afterLifeCount: UInt16
    public let beforeLifeCount: UInt16

    public init(afterLifeCount: UInt16, beforeLifeCount: UInt16) {
        self.afterLifeCount = afterLifeCount
        self.beforeLifeCount = beforeLifeCount
    }
}

public struct HistoricalBackfill: Equatable, Sendable {
    public private(set) var pages: [HistoricalReadingPage]

    public init(pages: [HistoricalReadingPage] = []) {
        self.pages = pages
    }

    public mutating func append(_ page: HistoricalReadingPage) {
        pages.append(page)
    }

    public var samples: [HistoricalReadingSample] {
        pages
            .flatMap(\.samples)
            .sorted { $0.lifeCount < $1.lifeCount }
    }

    public var firstLifeCount: UInt16? {
        samples.first?.lifeCount
    }

    public var lastLifeCount: UInt16? {
        samples.last?.lifeCount
    }

    public var gaps: [HistoricalBackfillGap] {
        let ordered = samples
        guard ordered.count > 1 else {
            return []
        }
        return zip(ordered, ordered.dropFirst()).compactMap { previous, next in
            next.lifeCount > previous.lifeCount + HistoricalReadingPage.sampleSpacingLifeCounts
                ? HistoricalBackfillGap(afterLifeCount: previous.lifeCount, beforeLifeCount: next.lifeCount)
                : nil
        }
    }

    public var isContiguous: Bool {
        gaps.isEmpty
    }
}

public enum BackfillStream: Equatable, Sendable {
    case historical
    case clinical

    var wireValue: UInt8 {
        wireValue(for: .libre3)
    }

    /// Second byte of the 7-byte backfill request (`01 <stream> arg from[4]`).
    /// Libre 3: historical `0x00`, clinical `0x01`. Lingo: historical `0x02`,
    /// clinical `0x03` (`docs/PROTOCOLO_LINGO.md` §6.1, Juggluco
    /// `bluetooth.cpp:712-719`). `.unknown` uses the Libre 3 values, but
    /// `Libre3DataPlaneState.reconnectBackfillCommands(family: .unknown)`
    /// never builds commands for it.
    public func wireValue(for family: SensorFamily) -> UInt8 {
        switch (self, family) {
        case (.historical, .lingo):
            return 0x02
        case (.clinical, .lingo):
            return 0x03
        case (.historical, .libre3), (.historical, .unknown):
            return 0x00
        case (.clinical, .libre3), (.clinical, .unknown):
            return 0x01
        }
    }

    var label: String {
        switch self {
        case .historical:
            return "historic"
        case .clinical:
            return "clinical"
        }
    }
}
