import Foundation

public enum DataPlaneChannel: String, CaseIterable, Sendable {
    case patchControl
    case patchStatus
    case glucoseData
    case historicData
    case eventLog
    case clinicalData
    case factoryData

    public init?(uuidString: String) {
        let lower = uuidString.lowercased()
        switch lower {
        case _ where lower.hasPrefix("08981338"):
            self = .patchControl
        case _ where lower.hasPrefix("08981482"):
            self = .patchStatus
        case _ where lower.hasPrefix("0898177a"):
            self = .glucoseData
        case _ where lower.hasPrefix("0898195a"):
            self = .historicData
        case _ where lower.hasPrefix("08981bee"):
            self = .eventLog
        case _ where lower.hasPrefix("08981ab8"):
            self = .clinicalData
        case _ where lower.hasPrefix("08981d24"):
            self = .factoryData
        default:
            return nil
        }
    }

    public var preferredInboundKind: DataPlanePacketKind? {
        switch self {
        case .patchStatus:
            return .kind2
        case .glucoseData:
            return .kind3
        case .historicData:
            return .kind4
        case .patchControl, .eventLog, .clinicalData, .factoryData:
            return nil
        }
    }
}

public enum DataPlaneDecodedPayload: Equatable, Sendable {
    case realtimeGlucose(RealtimeGlucoseReading)
    case lingoRealtime(LingoRealtimeReading)
    case patchStatus(PatchStatus)
    case historicalReadingPage(HistoricalReadingPage)
    case lingoHistoricalPage(LingoHistoricalPage)
    case clinicalReadingRecord(ClinicalReadingRecord)
    case lingoFastData(LingoFastData)
    case raw(Data)
}

public struct DataPlaneDecodedPacket: Equatable, Sendable {
    public let channel: DataPlaneChannel
    public let frame: DataFrame
    public let kind: DataPlanePacketKind
    public let preferredKind: DataPlanePacketKind?
    public let plaintext: Data
    public let payload: DataPlaneDecodedPayload

    public var usedPreferredKind: Bool {
        preferredKind == nil || preferredKind == kind
    }
}

/// Why a decrypted plaintext on a parsed channel ended up as `.raw`.
/// Holds no plaintext bytes (only lengths and the parser error text).
public struct DataPlaneDecodeFailure: Equatable, Sendable {
    public let channel: DataPlaneChannel
    public let family: SensorFamily
    public let plaintextLength: Int
    public let reason: String
}

/// Counter of unexpected `.raw` payloads (risk 3 of `docs/FORK_RWDK.md` §6).
/// Shared by copies of the same `DataPlaneDecoder`.
final class DataPlaneDecodeDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var last: DataPlaneDecodeFailure?

    func record(_ failure: DataPlaneDecodeFailure) {
        lock.lock()
        count += 1
        last = failure
        lock.unlock()
    }

    var unexpectedRawCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var lastFailure: DataPlaneDecodeFailure? {
        lock.lock()
        defer { lock.unlock() }
        return last
    }
}

public struct DataPlaneDecoder: Sendable {
    public let crypto: DataPlaneCrypto
    public let family: SensorFamily
    private let diagnostics = DataPlaneDecodeDiagnostics()

    /// `family` selects the payload parsers:
    /// - `.libre3`: realtime 29 B, patch status 12 B, historical/clinical 14 B (upstream).
    /// - `.lingo`: realtime 51 B, patch status 12/14 B, `LingoHistoricalPage`, `LingoFastData`.
    /// - `.unknown`: realtime dispatched by length (29 → Libre 3, 51 → Lingo);
    ///   other channels with the Libre 3 parsers. Unknown variants must not be
    ///   paired anyway; this only keeps diagnostics readable.
    public init(crypto: DataPlaneCrypto, family: SensorFamily = .libre3) {
        self.crypto = crypto
        self.family = family
    }

    /// Number of plaintexts on parsed channels (glucose, status, historic,
    /// clinical) that failed their parser and were returned as `.raw`.
    public var unexpectedRawCount: Int {
        diagnostics.unexpectedRawCount
    }

    /// Last parser failure behind an unexpected `.raw`.
    public var lastDecodeError: DataPlaneDecodeFailure? {
        diagnostics.lastFailure
    }

    public func decrypt(frame: DataFrame, channel: DataPlaneChannel) throws -> DataPlaneDecodedPacket {
        let preferredKind = channel.preferredInboundKind
        let result: DataPlaneDecryptResult
        if let preferredKind,
           let plaintext = try? crypto.decrypt(frame, kind: preferredKind) {
            // A tag failure here is expected for channels whose kind is
            // still probed; fall back to trying every descriptor below.
            result = DataPlaneDecryptResult(kind: preferredKind, plaintext: plaintext)
        } else {
            result = try crypto.decryptTryingAllKinds(frame)
        }

        return DataPlaneDecodedPacket(
            channel: channel,
            frame: frame,
            kind: result.kind,
            preferredKind: preferredKind,
            plaintext: result.plaintext,
            payload: decodePayload(channel: channel, plaintext: result.plaintext)
        )
    }

    /// Decode an already decrypted plaintext. Parser failures on parsed
    /// channels are counted in `unexpectedRawCount` / `lastDecodeError`.
    public func decodePayload(channel: DataPlaneChannel, plaintext: Data) -> DataPlaneDecodedPayload {
        do {
            switch channel {
            case .glucoseData:
                return try decodeRealtime(plaintext)
            case .patchStatus:
                return .patchStatus(try PatchStatus(plaintext: plaintext, family: family))
            case .historicData:
                if family == .lingo {
                    return .lingoHistoricalPage(try LingoHistoricalPage(plaintext: plaintext))
                }
                return .historicalReadingPage(try HistoricalReadingPage(plaintext: plaintext))
            case .clinicalData:
                // Clinical pages have a different layout than historical
                // (single time-point record, not 6 samples at 5-min stride).
                // See ClinicalReadingRecord / LingoFastData for field semantics.
                if family == .lingo {
                    return .lingoFastData(try LingoFastData(plaintext: plaintext))
                }
                return .clinicalReadingRecord(try ClinicalReadingRecord(plaintext: plaintext))
            case .patchControl, .eventLog, .factoryData:
                return .raw(plaintext)
            }
        } catch {
            diagnostics.record(
                DataPlaneDecodeFailure(
                    channel: channel,
                    family: family,
                    plaintextLength: plaintext.count,
                    reason: String(describing: error)
                )
            )
            return .raw(plaintext)
        }
    }

    private func decodeRealtime(_ plaintext: Data) throws -> DataPlaneDecodedPayload {
        switch family {
        case .lingo:
            return .lingoRealtime(try LingoRealtimeReading(plaintext: plaintext))
        case .libre3:
            return .realtimeGlucose(try RealtimeGlucoseReading(plaintext: plaintext))
        case .unknown:
            if plaintext.count == LingoRealtimeReading.plaintextSize {
                return .lingoRealtime(try LingoRealtimeReading(plaintext: plaintext))
            }
            return .realtimeGlucose(try RealtimeGlucoseReading(plaintext: plaintext))
        }
    }
}

/// Outcome of feeding one notification to `DataPlaneNotificationAssembler`.
public enum DataPlaneAssemblyResult: Equatable, Sendable {
    /// A complete frame of `targetLength` bytes (glucose) or a non-glucose
    /// notification passed through unchanged.
    case complete(Data)
    /// More glucose fragments are needed; `accumulated` bytes are buffered.
    case pending(accumulated: Int)
    /// The fragment would exceed `targetLength`: buffer and fragment were
    /// discarded and the assembler was reset (Juggluco `recover`).
    case overflow(accumulated: Int, fragmentLength: Int)
    /// An empty fragment arrived: buffer discarded and assembler reset.
    case emptyFragment(accumulated: Int)
}

/// Reassembles post-auth notification bodies before `DataFrame.parse`.
///
/// `glucoseData` frames are split across notifications with no header or
/// sequence number (pure concatenation, `docs/PROTOCOLO_LINGO.md` §2.3).
/// Fragments of any size (1...targetLength) are accumulated until exactly
/// `targetLength` bytes are buffered: 35 for Libre 3 (observed 15 + 20) and
/// 57 for Lingo (51 B plaintext + 4 B tag + 2 B counter). A fragment that
/// would exceed the target, or an empty fragment, discards everything and
/// resets, like Juggluco's `recover` (`Libre3GattCallback.java:1699-1731`);
/// the caller should treat that as a reason to resynchronise (reconnect).
/// Other channels pass through unchanged.
public final class DataPlaneNotificationAssembler: @unchecked Sendable {
    public static let libre3GlucoseFrameLength = 35
    public static let lingoGlucoseFrameLength = 57

    public let targetLength: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var _discardedFrameCount = 0
    private var _lastDiscard: DataPlaneAssemblyResult?

    public init(targetLength: Int = DataPlaneNotificationAssembler.libre3GlucoseFrameLength) {
        precondition(targetLength > 0, "targetLength must be positive")
        self.targetLength = targetLength
    }

    public convenience init(family: SensorFamily) {
        self.init(targetLength: Self.glucoseFrameLength(for: family))
    }

    public static func glucoseFrameLength(for family: SensorFamily) -> Int {
        family == .lingo ? lingoGlucoseFrameLength : libre3GlucoseFrameLength
    }

    /// Convenience wrapper: returns the complete frame, or `nil` while
    /// pending or after a discard (see `ingest` for the reason).
    public func feed(fragment: Data, channel: DataPlaneChannel) -> Data? {
        if case .complete(let frame) = ingest(fragment: fragment, channel: channel) {
            return frame
        }
        return nil
    }

    public func ingest(fragment: Data, channel: DataPlaneChannel) -> DataPlaneAssemblyResult {
        guard channel == .glucoseData else {
            return .complete(fragment)
        }

        lock.lock()
        defer { lock.unlock() }

        if fragment.isEmpty {
            return discard(.emptyFragment(accumulated: buffer.count))
        }
        if buffer.count + fragment.count > targetLength {
            return discard(.overflow(accumulated: buffer.count, fragmentLength: fragment.count))
        }
        buffer.append(fragment)
        if buffer.count == targetLength {
            let frame = buffer
            buffer = Data()
            return .complete(frame)
        }
        return .pending(accumulated: buffer.count)
    }

    /// Bytes currently buffered for an incomplete glucose frame.
    public var pendingByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Number of overflow / empty-fragment discards since creation.
    public var discardedFrameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _discardedFrameCount
    }

    /// Last `.overflow` or `.emptyFragment` result.
    public var lastDiscard: DataPlaneAssemblyResult? {
        lock.lock()
        defer { lock.unlock() }
        return _lastDiscard
    }

    public func reset() {
        lock.lock()
        buffer = Data()
        lock.unlock()
    }

    private func discard(_ result: DataPlaneAssemblyResult) -> DataPlaneAssemblyResult {
        buffer = Data()
        _discardedFrameCount += 1
        _lastDiscard = result
        return result
    }
}
