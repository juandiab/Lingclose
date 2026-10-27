import Foundation
import LingoCore
import RoundWhiteDiscKit
@testable import LingoScan

/// Coordinador con dobles: sensor sintético, enlace y NFC guionados, almacén de pairing en
/// memoria, SQLite temporal y reloj manual.
struct CoordinatorHarness {
    static let serial = "SYNTH0001"
    static let profile = SensorProfile(
        family: .lingo, productType: 9, securityVersion: 3, serial: serial,
        warmupMinutes: 60, wearMinutes: 20_160, firmwareHex: "01020304", stateByte: 1
    )
    static let activationEpoch: Int64 = 1_800_000_000 - 3_600

    let sensor: SyntheticLingoSensor
    let link: ScriptedSensorLink
    let nfc: ScriptedNFC
    let hook: RecordingRecoveryHook
    let pairing: InMemoryPairingStateStore
    let store: SQLiteStore
    let clock: TestClock
    let credentials: StaticCredentials
    let coordinator: SensorSessionCoordinator

    init(
        sensor: SyntheticLingoSensor = SyntheticLingoSensor(),
        signingKeys: [Data]? = nil,
        restored: [UUID] = [],
        pairing: InMemoryPairingStateStore? = nil,
        hook: RecordingRecoveryHook = RecordingRecoveryHook(),
        store: SQLiteStore? = nil,
        hangOnActivate: Bool = false,
        receiverIDGenerator: @escaping @Sendable () -> UInt32 = { 0x1234_5678 }
    ) async throws {
        self.sensor = sensor
        self.link = ScriptedSensorLink(sensor: sensor, restored: restored)
        self.nfc = ScriptedNFC(profile: Self.profile, response: Self.response(), hangOnActivate: hangOnActivate)
        self.hook = hook
        self.pairing = pairing ?? InMemoryPairingStateStore(recoveryHook: hook)
        self.store = try store ?? SQLiteStore(
            path: FileManager.default.temporaryDirectory.appending(path: "t08-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        )
        self.clock = TestClock()
        self.credentials = try StaticCredentials.synthetic(signingPublicKey: await sensor.signingPublicKey, keys: signingKeys)
        self.coordinator = SensorSessionCoordinator(
            link: link, nfc: nfc, pairingStore: self.pairing, credentials: credentials,
            store: self.store, clock: clock, receiverIDGenerator: receiverIDGenerator
        )
    }

    /// Respuesta `0xA0` sintética de 19 B: `00 a5 00 | MAC | PIN | tiempo LE | CRC`.
    static func response() -> ActivationResponse {
        var raw = Data([0x00, 0xA5, 0x00, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xC1, 0xC2, 0xC3, 0xC4])
        let t = UInt32(activationEpoch)
        raw.append(contentsOf: [UInt8(t & 0xFF), UInt8((t >> 8) & 0xFF), UInt8((t >> 16) & 0xFF), UInt8(t >> 24)])
        raw.append(contentsOf: [0x00, 0x00])
        return ActivationResponse(
            raw: raw, pin: raw.subdata(in: 9..<13), bleAddress: "11:22:33:44:55:66",
            activationTimeEpochS: activationEpoch, scannedSerial: serial, scannedStateByte: 1
        )
    }

    var state: SessionState { get async { await coordinator.state } }
    var history: [SessionState] { get async { await coordinator.history } }

    /// NFC `0xA1` → `prepared` → ticket → `0xA0` (sin esperar al BLE).
    @discardableResult
    func activate() async throws -> PreparedActivation {
        try await coordinator.identify()
        let prepared = try await coordinator.prepareActivation(for: Self.profile)
        let ticket = try await ActivationTicketFactory.issue(
            profile: Self.profile, sessionID: prepared.sessionID, confirmationID: UUID(), store: pairing
        )
        try await coordinator.activate(ticket: ticket)
        return prepared
    }

    /// Activa y espera la suscripción del plano de datos tras Phase 6.
    @discardableResult
    func pairUntilSubscribed() async throws -> PreparedActivation {
        let prepared = try await activate()
        guard await eventually({ await link.subscribeCount >= 1 }) else {
            throw HarnessError.timeout("suscripción; estado \(await state.logLabel)")
        }
        return prepared
    }

    func emitPatchStatus(currentLifeCount: Int16, patchState: Int8 = 4) async throws {
        let frame = try await sensor.frame(LingoTestFrames.patchStatus(currentLifeCount: currentLifeCount, patchState: patchState), kind: .kind2)
        await link.emit(.fragment(.patchStatus, frame))
    }

    /// Trama de 57 B en fragmentos de los tamaños dados.
    func emitRealtime(_ plaintext: Data, split: [Int] = [20, 20, 17]) async throws {
        let frame = try await sensor.frame(plaintext, kind: .kind3)
        precondition(frame.count == 57 && split.reduce(0, +) == 57)
        var offset = 0
        for size in split {
            await link.emit(.fragment(.glucoseData, frame.subdata(in: offset..<(offset + size))))
            offset += size
        }
    }

    enum HarnessError: Error { case timeout(String) }
}
