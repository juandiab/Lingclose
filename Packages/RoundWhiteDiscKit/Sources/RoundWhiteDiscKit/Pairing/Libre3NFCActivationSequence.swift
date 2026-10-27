import Foundation

/// Command sequence of one NFC tag session, independent of CoreNFC so it can
/// be tested on macOS. `Libre3NFCActivationReader` (iOS) only supplies the
/// transport.
///
/// Guarantees (27-oct, `docs/PROTOCOLO_LINGO.md` §1.7):
/// - `0xA1` (read-only) is retried up to `maxPatchInfoReads` times inside the
///   same tag session when the response cannot be parsed or the exchange
///   fails. Juggluco retries the same read up to 10 times (`AlgNfcV.java:49-51`).
/// - `0xA0`/`0xA8` is sent at most once per call, only after a valid `0xA1`
///   in this same session, and for the fresh-sensor mode only when that read
///   says `state == 1`. Its response is never retried: a failed or invalid
///   answer ends the session with an error.
public enum Libre3NFCActivationSequence {
    public static let maxPatchInfoReads = 3

    /// Reads `0xA1` until a frame parses, at most `maxReads` times.
    public static func readPatchInfo(
        maxReads: Int = maxPatchInfoReads,
        transceive: (_ code: UInt8, _ parameters: Data) async throws -> Data
    ) async throws -> Libre3NFCPatchInfo {
        var lastError: any Error = Libre3NFCError.noTag
        for _ in 0..<max(1, maxReads) {
            try Task.checkCancellation()
            do {
                let raw = try await transceive(0xa1, NFCActivationCommand.readPatchInfoCustomRequestParameters)
                return try Libre3NFCPatchInfo(raw: raw)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Full exchange for `mode`. `now` is only used when the mode carries no
    /// explicit activation time.
    public static func run(
        mode: Libre3NFCScanMode,
        maxPatchInfoReads: Int = maxPatchInfoReads,
        now: () -> Date = { Date() },
        transceive: (_ code: UInt8, _ parameters: Data) async throws -> Data
    ) async throws -> Libre3NFCScanResult {
        let patchInfo = try await readPatchInfo(maxReads: maxPatchInfoReads, transceive: transceive)

        let commandCode: NFCActivationCommandCode
        let receiverID: UInt32
        let explicitTime: UInt32?
        switch mode {
        case .readPatchInfo:
            return Libre3NFCScanResult(patchInfo: patchInfo)
        case .activateFreshSensor(let id, let time):
            guard patchInfo.recommendedCommandCode == .activate else {
                throw Libre3NFCError.unexpectedSensorState(patchInfo: patchInfo)
            }
            (commandCode, receiverID, explicitTime) = (.activate, id, time)
        case .switchReceiver(let id, let time):
            guard patchInfo.recommendedCommandCode == .switchReceiver else {
                throw Libre3NFCError.unexpectedSensorState(patchInfo: patchInfo)
            }
            (commandCode, receiverID, explicitTime) = (.switchReceiver, id, time)
        case .activateOrSwitchReceiver(let id, let time):
            (commandCode, receiverID, explicitTime) = (patchInfo.recommendedCommandCode, id, time)
        case .forceActivationCommand(let code, let id, let time):
            (commandCode, receiverID, explicitTime) = (code, id, time)
        }

        let timeSeconds = explicitTime ?? defaultActivationTimeSeconds(now: now())
        let parameters = NFCActivationCommand.customRequestParameters(timeSeconds: timeSeconds, receiverID: receiverID)
        // Single write: no retry of 0xA0/0xA8 in any case.
        let activationRaw = try await transceive(commandCode.rawValue, parameters)
        let activation: Libre3NFCActivationResponse
        do {
            activation = try Libre3NFCActivationResponse(raw: activationRaw)
        } catch Libre3NFCError.invalidActivationResponse(let raw) {
            throw Libre3NFCError.invalidActivationResponseForPatch(
                commandCode: commandCode,
                patchInfo: patchInfo,
                raw: raw
            )
        }
        return Libre3NFCScanResult(
            patchInfo: patchInfo,
            commandCode: commandCode,
            commandParameters: parameters,
            activationResponse: activation
        )
    }

    static func defaultActivationTimeSeconds(now: Date) -> UInt32 {
        let seconds = UInt64(max(0, now.timeIntervalSince1970.rounded(.down)))
        return UInt32(truncatingIfNeeded: max(0, Int64(seconds) - 1))
    }
}
