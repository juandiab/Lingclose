import Foundation

// Plaintext builders for patchControl writes.
//
// Each command is exactly 7 bytes before the post-auth AES-CCM data-plane
// wrapper turns it into an 11-byte encrypted body plus a 2-byte sequence.

public struct PatchControlCommand: Equatable, Sendable {
    public let label: String
    public let plaintext: Data

    public init(label: String, plaintext: Data) throws {
        guard plaintext.count == 7 else {
            throw PatchControlCommandError.wrongPlaintextSize(plaintext.count)
        }
        self.label = label
        self.plaintext = plaintext
    }

    public static func historicalBackfillGreaterEqual(
        lifeCount: UInt16,
        selector: UInt8 = 0x01,
        family: SensorFamily = .libre3
    ) -> PatchControlCommand {
        backfillGreaterEqual(stream: .historical, lifeCount: lifeCount, selector: selector, family: family)
    }

    public static func clinicalBackfillGreaterEqual(
        lifeCount: UInt16,
        selector: UInt8 = 0x01,
        family: SensorFamily = .libre3
    ) -> PatchControlCommand {
        backfillGreaterEqual(stream: .clinical, lifeCount: lifeCount, selector: selector, family: family)
    }

    /// `01 <stream> <selector> from[4 LE]`. `from` is an int32 on the wire
    /// (Juggluco `struct RequestData`); lifeCounts fit in 16 bits, so bytes
    /// 5-6 stay `00 00`.
    public static func backfillGreaterEqual(
        stream: BackfillStream,
        lifeCount: UInt16,
        selector: UInt8 = 0x01,
        family: SensorFamily = .libre3
    ) -> PatchControlCommand {
        makeRangeCommand(
            label: "\(stream.label) >= \(lifeCount)",
            command: 0x01,
            stream: stream.wireValue(for: family),
            selector: selector,
            lifeCount: lifeCount,
            aux: nil
        )
    }

    /// Lingo backfill requests sent after a patch status, following the
    /// conditions of `docs/PROTOCOLO_LINGO.md` §6.1 (Juggluco
    /// `Libre3GattCallback.java:1776-1800`):
    ///
    /// - historical `01 02 01 from`: only when
    ///   `((currentLifeCount - 16) / 5) * 5 > lastHistoricLifeCountReceived`;
    ///   `from = max(lastHistoricLifeCountReceived, 5)`.
    /// - clinical `01 03 01 from`: `from = lastLifeCountReceived + 1`
    ///   (Juggluco's `getlastLifeCountReceived`), only when `from < currentLifeCount`.
    ///   Without any received lifeCount no clinical request is built (decision
    ///   T-03: avoid asking a long-running sensor for its whole minute log).
    ///
    /// `currentLifeCount < 0` (patch status sentinel) builds nothing.
    public static func lingoBackfillCommands(
        currentLifeCount: Int,
        lastHistoricLifeCountReceived: Int?,
        lastLifeCountReceived: Int?,
        selector: UInt8 = 0x01,
        includeClinical: Bool = true
    ) -> [PatchControlCommand] {
        guard currentLifeCount >= 0 else {
            return []
        }
        var commands: [PatchControlCommand] = []
        let lastHistoric = lastHistoricLifeCountReceived ?? 0
        let historicTarget = ((currentLifeCount - 16) / 5) * 5
        if historicTarget > lastHistoric {
            let from = max(lastHistoric, 5)
            if let lifeCount = UInt16(exactly: from) {
                commands.append(
                    historicalBackfillGreaterEqual(lifeCount: lifeCount, selector: selector, family: .lingo)
                )
            }
        }
        if includeClinical, let last = lastLifeCountReceived {
            let from = last + 1
            if from < currentLifeCount, let lifeCount = UInt16(exactly: from) {
                commands.append(
                    clinicalBackfillGreaterEqual(lifeCount: lifeCount, selector: selector, family: .lingo)
                )
            }
        }
        return commands
    }

    public static func eventLog(index: UInt8) -> PatchControlCommand {
        PatchControlCommand(
            label: "event log >= \(index)",
            plaintext: Data([0x04, index, 0x00, 0x00, 0x00, 0x00, 0x00]),
            unchecked: ()
        )
    }

    public static func factoryData() -> PatchControlCommand {
        PatchControlCommand(
            label: "factory data",
            plaintext: Data([0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            unchecked: ()
        )
    }

    /// Request sensor shutdown/end-session.
    ///
    /// This is a terminal patch-control command. It is not needed for routine
    /// disconnect, reconnect, or backfill workflows.
    public static func shutdownPatch() -> PatchControlCommand {
        PatchControlCommand(
            label: "shutdown patch",
            plaintext: Data([0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            unchecked: ()
        )
    }

    private init(label: String, plaintext: Data, unchecked: Void) {
        self.label = label
        self.plaintext = plaintext
    }

    private static func makeRangeCommand(
        label: String,
        command: UInt8,
        stream: UInt8,
        selector: UInt8,
        lifeCount: UInt16,
        aux: UInt16?
    ) -> PatchControlCommand {
        var bytes = Data([
            command,
            stream,
            selector,
            UInt8(lifeCount & 0xff),
            UInt8((lifeCount >> 8) & 0xff),
            0x00,
            0x00,
        ])
        if let aux {
            bytes[5] = UInt8(aux & 0xff)
            bytes[6] = UInt8((aux >> 8) & 0xff)
        }
        return PatchControlCommand(label: label, plaintext: bytes, unchecked: ())
    }
}

public enum PatchControlCommandError: Error, Equatable {
    case wrongPlaintextSize(Int)
}
