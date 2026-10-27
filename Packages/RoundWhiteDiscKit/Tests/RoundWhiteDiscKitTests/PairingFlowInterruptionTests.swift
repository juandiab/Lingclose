import CryptoKit
import XCTest
@testable import RoundWhiteDiscKit

/// T-02: `noTrustedSigningKeys` and `authenticationInterrupted`. All keys and
/// certificates are generated at test time.
final class PairingFlowInterruptionTests: XCTestCase {
    private func phoneCert() throws -> PhoneCert {
        try PhoneCert(raw: T02Fixtures.identity().certificate)
    }

    // MARK: - noTrustedSigningKeys

    func testEmptySigningKeysRejectedByFullInit() throws {
        XCTAssertThrowsError(
            try PairingFlow(transport: ScriptedCommandPairingTransport(), phoneCert: phoneCert(), sensorCertSigningKeys: [])
        ) { error in
            guard case PairingFlowError.noTrustedSigningKeys = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testEmptySigningKeysRejectedByReconnectInit() {
        XCTAssertThrowsError(
            try PairingFlow(transport: ScriptedCommandPairingTransport(), sensorCertSigningKeys: [])
        ) { error in
            guard case PairingFlowError.noTrustedSigningKeys = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testTestingInitializerAllowsEmptyKeys() throws {
        XCTAssertNoThrow(
            try PairingFlow(
                transport: ScriptedCommandPairingTransport(),
                phoneCert: phoneCert(),
                sensorCertSigningKeys: [],
                allowEmptySigningKeysForTesting: true
            )
        )
    }

    // MARK: - authenticationInterrupted

    func testStreamEndAfterLoadDoneIsCertificateAcceptanceInterruption() async throws {
        let transport = ScriptedCommandPairingTransport(commandResponses: [], end: .streamEnded)
        let flow = try PairingFlow(transport: transport, phoneCert: phoneCert())

        do {
            _ = try await flow.runCommandGatedAuthorizationHandshake(
                tail4: Data([1, 2, 3, 4]),
                phase5RawKeyProvider: { _ in Data(count: 16) }
            )
            XCTFail("expected interruption")
        } catch PairingFlowError.authenticationInterrupted(let phase, let evidence) {
            XCTAssertEqual(phase, .certificateAcceptance)
            XCTAssertEqual(evidence.lastCommandSent, 0x03)
            XCTAssertNil(evidence.lastBytesReceived)
            XCTAssertGreaterThanOrEqual(evidence.elapsed, 0)
            XCTAssertTrue(evidence.underlying.contains("notifyStreamEnded"), evidence.underlying)
        }
        let commands = await transport.commandWrites
        XCTAssertEqual(commands, [0x01, 0x02, 0x03])
        let writes = await transport.messageWrites
        XCTAssertEqual(writes.map(\.count), [PhoneCert.totalSize])
    }

    func testTimeoutAfterLoadDoneIsCertificateAcceptanceInterruption() async throws {
        let transport = ScriptedCommandPairingTransport(commandResponses: [], end: .timeout)
        let flow = try PairingFlow(transport: transport, phoneCert: phoneCert())

        do {
            _ = try await flow.runCommandGatedFirstPairPreamble()
            XCTFail("expected interruption")
        } catch PairingFlowError.authenticationInterrupted(let phase, let evidence) {
            XCTAssertEqual(phase, .certificateAcceptance)
            XCTAssertEqual(evidence.lastCommandSent, 0x03)
            XCTAssertTrue(evidence.underlying.contains("notifyTimeout"), evidence.underlying)
        }
    }

    func testUnexpectedResponseToLoadDoneIsInterruptionNotRejection() async throws {
        // A byte other than 0x04 is not documented as a rejection code, so it
        // is reported as an interruption with the raw byte as evidence.
        let transport = ScriptedCommandPairingTransport(commandResponses: [Data([0x05])], end: .streamEnded)
        let flow = try PairingFlow(transport: transport, phoneCert: phoneCert())

        do {
            _ = try await flow.runCommandGatedFirstPairPreamble()
            XCTFail("expected interruption")
        } catch PairingFlowError.authenticationInterrupted(let phase, let evidence) {
            XCTAssertEqual(phase, .certificateAcceptance)
            XCTAssertEqual(evidence.lastCommandSent, 0x03)
            XCTAssertEqual(evidence.lastBytesReceived, Data([0x05]))
            XCTAssertTrue(evidence.underlying.contains("unexpectedCommandResponse"), evidence.underlying)
        }
    }

    func testStreamEndAfterEphemeralIsEphemeralInterruption() async throws {
        let signer = P256.Signing.PrivateKey()
        let sensorCert = try T02Fixtures.sensorCert(signedBy: signer)
        let transport = ScriptedCommandPairingTransport(
            commandResponses: [Data([0x04]), Data([0x0a])],
            certNotifies: [sensorCert],
            end: .streamEnded
        )
        let flow = try PairingFlow(
            transport: transport,
            phoneCert: phoneCert(),
            sensorCertSigningKeys: [signer.publicKey.x963Representation]
        )

        do {
            _ = try await flow.runCommandGatedFirstPairPreamble()
            XCTFail("expected interruption")
        } catch PairingFlowError.authenticationInterrupted(let phase, let evidence) {
            XCTAssertEqual(phase, .ephemeral)
            XCTAssertEqual(evidence.lastCommandSent, 0x0e)
            XCTAssertEqual(evidence.lastBytesReceived, sensorCert)
        }
        let commands = await transport.commandWrites
        XCTAssertEqual(commands, [0x01, 0x02, 0x03, 0x09, 0x0d, 0x0e])
    }

    func testSensorCertSignedByOtherKeyFailsVerificationAndIsNotWrapped() async throws {
        let transport = ScriptedCommandPairingTransport(
            commandResponses: [Data([0x04]), Data([0x0a])],
            certNotifies: [try T02Fixtures.sensorCert(signedBy: P256.Signing.PrivateKey())],
            end: .streamEnded
        )
        let flow = try PairingFlow(
            transport: transport,
            phoneCert: phoneCert(),
            sensorCertSigningKeys: [P256.Signing.PrivateKey().publicKey.x963Representation]
        )

        do {
            _ = try await flow.runCommandGatedFirstPairPreamble()
            XCTFail("expected verification failure")
        } catch PairingFlowError.sensorCertificateVerificationFailed {
            // expected: a credential-shaped failure, distinct from interruption
        }
        let commands = await transport.commandWrites
        XCTAssertEqual(commands, [0x01, 0x02, 0x03, 0x09], "0x0d must not be sent after a failed verification")
    }

    func testCachedReconnectStreamEndIsChallengeInterruption() async throws {
        let transport = ScriptedCommandPairingTransport(commandResponses: [], end: .streamEnded)
        let flow = try PairingFlow(transport: transport)

        do {
            _ = try await flow.runCachedReconnectHandshake(tail4: Data([1, 2, 3, 4]), phase5RawKey: Data(count: 16))
            XCTFail("expected interruption")
        } catch PairingFlowError.authenticationInterrupted(let phase, let evidence) {
            XCTAssertEqual(phase, .challenge)
            XCTAssertEqual(evidence.lastCommandSent, 0x11)
        }
    }

    func testCachedReconnectStreamEndBeforePhase6IsPhase6Interruption() async throws {
        let r1Wire = Data(repeating: 0x11, count: 16) + Data(repeating: 0x22, count: 7)
        let transport = ScriptedCommandPairingTransport(
            commandResponses: [Data([0x08]), Data([0x08])],
            challengeNotifies: [r1Wire],
            end: .streamEnded
        )
        let flow = try PairingFlow(transport: transport)

        do {
            _ = try await flow.runCachedReconnectHandshake(tail4: Data([1, 2, 3, 4]), phase5RawKey: Data(count: 16))
            XCTFail("expected interruption")
        } catch PairingFlowError.authenticationInterrupted(let phase, let evidence) {
            XCTAssertEqual(phase, .phase6)
            XCTAssertEqual(evidence.lastCommandSent, 0x08)
            XCTAssertEqual(evidence.lastBytesReceived, Data([0x08]))
        }
    }

    func testInterruptionClassifierOnlyMatchesTransportShapes() {
        XCTAssertTrue(PairingFlow.isInterruption(SensorSessionTransportError.notifyStreamEnded(have: 0, want: 0)))
        XCTAssertTrue(PairingFlow.isInterruption(SensorSessionTransportError.notifyTimeout(characteristic: "x", seconds: 2)))
        XCTAssertTrue(PairingFlow.isInterruption(
            PairingFlowError.unexpectedCommandResponse(label: "x", expectedPrefix: Data([0x04]), actual: Data([0x05]))
        ))
        XCTAssertFalse(PairingFlow.isInterruption(PairingFlowError.sensorCertificateVerificationFailed))
        XCTAssertFalse(PairingFlow.isInterruption(PairingFlowError.writeTimeout(label: "x", seconds: 2)))
        XCTAssertFalse(PairingFlow.isInterruption(PairingFlowError.phase6VerificationFailed("x")))
    }
}

/// Command-gated transport with scripted responses. When a script runs out it
/// fails the wait the way `SensorSessionTransport` does when the link drops
/// (`notifyStreamEnded`) or the sensor goes silent (`notifyTimeout`).
private actor ScriptedCommandPairingTransport: CommandPairingTransport {
    enum End {
        case streamEnded
        case timeout
    }

    private var commandResponses: [Data]
    private var certNotifies: [Data]
    private var challengeNotifies: [Data]
    private let end: End
    private(set) var commandWrites: [UInt8] = []
    private(set) var messageWrites: [Data] = []

    init(
        commandResponses: [Data] = [],
        certNotifies: [Data] = [],
        challengeNotifies: [Data] = [],
        end: End = .streamEnded
    ) {
        self.commandResponses = commandResponses
        self.certNotifies = certNotifies
        self.challengeNotifies = challengeNotifies
        self.end = end
    }

    private func endError(_ characteristic: String) -> Error {
        switch end {
        case .streamEnded:
            return SensorSessionTransportError.notifyStreamEnded(have: 0, want: 0)
        case .timeout:
            return SensorSessionTransportError.notifyTimeout(characteristic: characteristic, seconds: 2)
        }
    }

    func write(_ message: Data, to characteristic: BleCharRef) async throws {
        messageWrites.append(message)
    }

    func awaitNotify(on characteristic: BleCharRef, exactly n: Int) async throws -> Data {
        switch characteristic {
        case .certHandshake:
            guard !certNotifies.isEmpty else { throw endError(characteristic.rawValue) }
            return certNotifies.removeFirst()
        case .challenge:
            guard !challengeNotifies.isEmpty else { throw endError(characteristic.rawValue) }
            return challengeNotifies.removeFirst()
        }
    }

    func writeCommand(_ command: UInt8) async throws {
        commandWrites.append(command)
    }

    func awaitCommandResponse(timeout: TimeInterval) async throws -> Data {
        guard !commandResponses.isEmpty else { throw endError("secCommandResponse") }
        return commandResponses.removeFirst()
    }
}
