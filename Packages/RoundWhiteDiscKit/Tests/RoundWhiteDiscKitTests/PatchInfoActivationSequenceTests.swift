import XCTest
@testable import RoundWhiteDiscKit

/// 27-oct: "patchInfo inválido (64 B)" en dos de tres intentos de activación con
/// el sensor real (`docs/PROTOCOLO_LINGO.md` §1.7). Tramas sintéticas: serial
/// `SYNTH0001`, sin bytes de ningún sensor real.
final class PatchInfoActivationSequenceTests: XCTestCase {
    /// `00 A5 00` + `firstnfc` sintético (Lingo pt 9, sv 3) con CRC Abbott válido.
    static func frame(state: UInt8 = 1, serial: String = "SYNTH0001") -> Data {
        var body: [UInt8] = [0x03, 0x00, 0x08, 0x00, 0x01, 0x00, 0xC0, 0x4E, 0x01, 0x02, 0x03, 0x04, 0x09, 0x0C, state]
        body += Array(serial.utf8)
        precondition(body.count == 24)
        let crc = NFCActivationCommand.abbottCRC16(Data(body))
        return Data([0x00, 0xa5, 0x00] + body + [UInt8(crc & 0xff), UInt8(crc >> 8)])
    }

    /// 64 B: 7 B de basura, la trama sin el byte de flags (`A5 00 …`, 28 B) y relleno.
    static func embedded64() -> Data {
        var out = Data([0x12, 0x34, 0x56, 0x00, 0xff, 0x01, 0x02])
        out += frame().dropFirst()
        out += Data(repeating: 0xee, count: 64 - out.count)
        precondition(out.count == 64)
        return out
    }

    /// 64 B sin trama válida, pero con `A5 00` en medio (CRC incorrecto).
    static func garbage64() -> Data {
        var out = Data([0x12, 0x34])
        var bad = frame()
        bad[10] ^= 0xff
        out += bad.dropFirst()
        out += Data(repeating: 0x5a, count: 64 - out.count)
        precondition(out.count == 64)
        return out
    }

    static func bytes(_ hex: String) -> Data {
        let chars = Array(hex)
        return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! })
    }

    static func response19() -> Data {
        Data([0x00, 0xa5, 0x00, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0xc1, 0xc2, 0xc3, 0xc4, 0x10, 0x20, 0x30, 0x40, 0x00, 0x00])
    }

    // MARK: - Parser

    func testCRCOfFirstNFCMatchesTheTwoJugglucoSamplesAlgorithm() throws {
        // Fixture ya presente en el repo (Libre 3 sintético, `NFCActivationCommandTests`).
        let existing = try Libre3NFCPatchInfo(raw: Self.bytes("00a50001000200010060541e020401040c04305252433938394151c6ca"))
        XCTAssertTrue(existing.hasValidCRC)
        XCTAssertTrue(try Libre3NFCPatchInfo(raw: Self.frame()).hasValidCRC)
    }

    func testDirectFrameIsUnchanged() throws {
        let info = try Libre3NFCPatchInfo(raw: Self.frame())
        XCTAssertEqual(info.raw, Self.frame())
        XCTAssertFalse(info.wasExtractedFromLongerResponse)
        XCTAssertEqual(info.family, .lingo)
        XCTAssertEqual(info.stateByte, 1)
        XCTAssertEqual(info.serialNumber, "SYNTH0001")
    }

    func testSixtyFourByteResponseContainingTheFrameIsNormalised() throws {
        let info = try Libre3NFCPatchInfo(raw: Self.embedded64())
        XCTAssertEqual(info.inputRaw.count, 64)
        XCTAssertEqual(info.raw, Self.frame())
        XCTAssertTrue(info.wasExtractedFromLongerResponse)
        XCTAssertEqual(info.productType, 9)
        XCTAssertEqual(info.securityVersion, 3)
        XCTAssertEqual(info.stateByte, 1)
        XCTAssertEqual(info.serialNumber, "SYNTH0001")
        XCTAssertEqual(info.recommendedCommandCode, .activate)
    }

    func testSixtyFourByteGarbageIsStillRejected() {
        XCTAssertThrowsError(try Libre3NFCPatchInfo(raw: Self.garbage64())) { error in
            XCTAssertEqual(error as? Libre3NFCError, .invalidPatchInfo(Self.garbage64()))
        }
        XCTAssertThrowsError(try Libre3NFCPatchInfo(raw: Data(repeating: 0, count: 64)))
    }

    // MARK: - Secuencia de la sesión NFC

    func testEmbeddedFrameActivatesWithASingleA0() async throws {
        var sent: [UInt8] = []
        let result = try await Libre3NFCActivationSequence.run(mode: .activateFreshSensor(receiverID: 0x1234_5678, timeSeconds: 1000)) { code, _ in
            sent.append(code)
            return code == 0xa1 ? Self.embedded64() : Self.response19()
        }
        XCTAssertEqual(sent, [0xa1, 0xa0])
        XCTAssertEqual(result.commandCode, .activate)
        XCTAssertEqual(result.patchInfo.serialNumber, "SYNTH0001")
        XCTAssertNotNil(result.activationResponse)
    }

    func testGarbageReadIsRetriedInTheSameSessionBeforeA0() async throws {
        var sent: [UInt8] = []
        var reads = 0
        let result = try await Libre3NFCActivationSequence.run(mode: .activateFreshSensor(receiverID: 7, timeSeconds: 1000)) { code, _ in
            sent.append(code)
            guard code == 0xa1 else { return Self.response19() }
            reads += 1
            return reads < 3 ? Self.garbage64() : Self.frame()
        }
        XCTAssertEqual(sent, [0xa1, 0xa1, 0xa1, 0xa0])
        XCTAssertEqual(result.commandCode, .activate)
    }

    func testPersistentGarbageFailsWithoutSendingA0() async {
        var sent: [UInt8] = []
        do {
            _ = try await Libre3NFCActivationSequence.run(mode: .activateFreshSensor(receiverID: 7, timeSeconds: 1000)) { code, _ in
                sent.append(code)
                return code == 0xa1 ? Self.garbage64() : Self.response19()
            }
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? Libre3NFCError, .invalidPatchInfo(Self.garbage64()))
        }
        XCTAssertEqual(sent, [0xa1, 0xa1, 0xa1], "tres lecturas 0xA1 y ningún 0xA0")
    }

    func testTransportErrorOnA1IsRetriedButNeverOnA0() async {
        struct Lost: Error {}
        var sent: [UInt8] = []
        var reads = 0
        do {
            _ = try await Libre3NFCActivationSequence.run(mode: .activateFreshSensor(receiverID: 7, timeSeconds: 1000)) { code, _ in
                sent.append(code)
                if code == 0xa1 {
                    reads += 1
                    if reads == 1 { throw Lost() }
                    return Self.frame()
                }
                throw Lost()
            }
            XCTFail("debía fallar")
        } catch {
            XCTAssertTrue(error is Lost)
        }
        XCTAssertEqual(sent, [0xa1, 0xa1, 0xa0], "0xA0 una sola vez aunque falle")
    }

    func testInvalidA0ResponseIsNotRetried() async {
        var sent: [UInt8] = []
        do {
            _ = try await Libre3NFCActivationSequence.run(mode: .activateFreshSensor(receiverID: 7, timeSeconds: 1000)) { code, _ in
                sent.append(code)
                return code == 0xa1 ? Self.frame() : Data(repeating: 0x00, count: 64)
            }
            XCTFail("debía fallar")
        } catch {
            guard case .invalidActivationResponseForPatch? = error as? Libre3NFCError else {
                return XCTFail("error inesperado \(error)")
            }
        }
        XCTAssertEqual(sent, [0xa1, 0xa0])
    }

    func testNotFreshSensorNeverGetsA0() async {
        var sent: [UInt8] = []
        do {
            _ = try await Libre3NFCActivationSequence.run(mode: .activateFreshSensor(receiverID: 7, timeSeconds: 1000)) { code, _ in
                sent.append(code)
                return Self.frame(state: 4)
            }
            XCTFail("debía fallar")
        } catch {
            guard case .unexpectedSensorState? = error as? Libre3NFCError else {
                return XCTFail("error inesperado \(error)")
            }
        }
        XCTAssertEqual(sent, [0xa1])
    }

    func testReadModeOnlySendsA1() async throws {
        var sent: [UInt8] = []
        let result = try await Libre3NFCActivationSequence.run(mode: .readPatchInfo) { code, _ in
            sent.append(code)
            return Self.embedded64()
        }
        XCTAssertEqual(sent, [0xa1])
        XCTAssertNil(result.commandCode)
    }
}
