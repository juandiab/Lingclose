import XCTest
@testable import RoundWhiteDiscKit

/// T-02: sensor family detection from synthetic patch info (no real capture,
/// no real serial number) and persistence of the family in sensor state.
final class LingoFamilyTests: XCTestCase {
    /// 29-byte normalised A1 frame: `00 A5 00 | sec u16 LE @3 | region @5 |
    /// generation @7 | wear @9 | firmware @11 | productType @15 | warmup @16 |
    /// state @17 | serial[9] @18 | crc[2] @27`.
    private func syntheticPatchInfoFrame(productType: UInt8, securityVersion: UInt16, length: Int = 29) -> Data {
        var bytes: [UInt8] = [0x00, 0xa5, 0x00]
        bytes += [UInt8(securityVersion & 0xff), UInt8(securityVersion >> 8)]
        bytes += [0x01, 0x00]               // region
        bytes += [0x01, 0x00]               // generation
        bytes += [0x60, 0x54]               // wear 21600 min
        bytes += [0x1e, 0x02, 0x04, 0x01]   // firmware
        bytes += [productType]              // @15
        bytes += [0x0c]                     // warmup 12 * 5 = 60 min
        bytes += [0x01]                     // state: not activated
        bytes += Array("SYNTHETIC".utf8)    // @18..<27, fake serial
        bytes += [0x00, 0x00]               // crc (not validated)
        XCTAssertEqual(bytes.count, 29)
        return Data(bytes.prefix(length))
    }

    func testProductType9SecurityVersion3IsLingo() throws {
        let info = try Libre3NFCPatchInfo(raw: syntheticPatchInfoFrame(productType: 9, securityVersion: 3))
        XCTAssertEqual(info.productType, 9)
        XCTAssertEqual(info.securityVersion, 3)
        XCTAssertEqual(info.family, .lingo)
        XCTAssertEqual(info.serialNumber, "SYNTHETIC")
    }

    func testProductType9WithOtherSecurityVersionIsUnknown() throws {
        for version: UInt16 in [0, 1, 2, 4, 0x0300] {
            let info = try Libre3NFCPatchInfo(raw: syntheticPatchInfoFrame(productType: 9, securityVersion: version))
            XCTAssertEqual(info.family, .unknown, "sec \(version)")
        }
    }

    func testProductType4IsLibre3() throws {
        let info = try Libre3NFCPatchInfo(raw: syntheticPatchInfoFrame(productType: 4, securityVersion: 1))
        XCTAssertEqual(info.family, .libre3)
        XCTAssertEqual(SensorFamily(productType: 4, securityVersion: 3), .libre3)
    }

    func testOtherProductTypesAreUnknown() throws {
        for productType: UInt8 in [0, 3, 5, 8, 10, 0xff] {
            XCTAssertEqual(SensorFamily(productType: productType, securityVersion: 3), .unknown)
        }
    }

    func testCapturedLibre3PatchInfoStaysLibre3() throws {
        let fresh = try Libre3NFCPatchInfo(
            raw: Data(t02Hex: "00a50001000200010060541e020401040c0130525243393839415151ff17")
        )
        XCTAssertEqual(fresh.family, .libre3)
    }

    func testPatchInfoSizeGuardRejects28Bytes() {
        XCTAssertThrowsError(
            try Libre3NFCPatchInfo(raw: syntheticPatchInfoFrame(productType: 9, securityVersion: 3, length: 28))
        )
    }

    func testFourByteActivationErrorResponseIsRejectedBySizeGuard() {
        // `00 A5 01 B1`: Juggluco's account-ID rejection shape (nfc.cpp).
        // T-03: no longer `invalidActivationResponse`; parsed as an explicit
        // activation error (see LingoDataPlaneTests for the full matrix).
        XCTAssertThrowsError(try Libre3NFCActivationResponse(raw: Data([0x00, 0xa5, 0x01, 0xb1]))) { error in
            XCTAssertEqual(error as? Libre3NFCActivationError, Libre3NFCActivationError(code: 0xb1))
        }
    }

    func testSensorFamilyCodableRawValues() throws {
        XCTAssertEqual(SensorFamily.lingo.rawValue, "lingo")
        XCTAssertEqual(SensorFamily.lingo.productType, 9)
        XCTAssertEqual(SensorFamily.libre3.productType, 4)
        XCTAssertNil(SensorFamily.unknown.productType)
        let encoded = try JSONEncoder().encode([SensorFamily.lingo])
        XCTAssertEqual(try JSONDecoder().decode([SensorFamily].self, from: encoded), [.lingo])
    }

    // MARK: - Libre3SensorStateLoader

    func testOldStateJSONWithoutT02FieldsStillLoads() throws {
        let json = Data(#"{"serialNumber":"SYNTH0001","blePIN":"01020304","receiverID":"78563412","warmupDurationMinutes":60}"#.utf8)
        let state = try Libre3SensorStateLoader.load(fromJSON: json)
        XCTAssertEqual(state.serialNumber, "SYNTH0001")
        XCTAssertEqual(state.warmupDurationMinutes, 60)
        XCTAssertNil(state.productType)
        XCTAssertNil(state.securityVersion)
        XCTAssertNil(state.identityLabel)
        XCTAssertNil(state.family)

        let reencoded = String(decoding: try Libre3SensorStateLoader.jsonData(from: state), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("productType"))
        XCTAssertFalse(reencoded.contains("family"))
    }

    func testNewStateJSONPreservesT02FieldsOnReserialize() throws {
        let json = Data(#"{"blePIN":"01020304","productType":9,"securityVersion":3,"identityLabel":"lingo-test","family":"lingo"}"#.utf8)
        let state = try Libre3SensorStateLoader.load(fromJSON: json)
        XCTAssertEqual(state.productType, 9)
        XCTAssertEqual(state.securityVersion, 3)
        XCTAssertEqual(state.identityLabel, "lingo-test")
        XCTAssertEqual(state.family, .lingo)

        let roundTripped = try Libre3SensorStateLoader.load(fromJSON: Libre3SensorStateLoader.jsonData(from: state))
        XCTAssertEqual(roundTripped, state)

        // Updating glucose metadata keeps the new fields.
        let updated = try state.updatingLastGlucose(lifeCount: 10, mgDL: 100)
        XCTAssertEqual(updated.family, .lingo)
        XCTAssertEqual(updated.identityLabel, "lingo-test")
    }

    func testUnrecognisedFamilyStringDecodesAsNil() throws {
        let json = Data(#"{"blePIN":"01020304","productType":9,"family":"ketone"}"#.utf8)
        let state = try Libre3SensorStateLoader.load(fromJSON: json)
        XCTAssertEqual(state.productType, 9)
        XCTAssertNil(state.family)
    }

    func testApplyingSensorCycleRecordsFamily() throws {
        let info = try Libre3NFCPatchInfo(raw: syntheticPatchInfoFrame(productType: 9, securityVersion: 3))
        let state = try Libre3SensorState(serialNumber: nil, blePIN: Data([1, 2, 3, 4]))
            .applyingSensorCycle(from: info)
            .applyingIdentityLabel("lingo-test")
        XCTAssertEqual(state.productType, 9)
        XCTAssertEqual(state.securityVersion, 3)
        XCTAssertEqual(state.family, .lingo)
        XCTAssertEqual(state.identityLabel, "lingo-test")
        XCTAssertEqual(state.warmupDurationMinutes, 60)
    }
}

extension Data {
    init(t02Hex hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }

    var t02Hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
