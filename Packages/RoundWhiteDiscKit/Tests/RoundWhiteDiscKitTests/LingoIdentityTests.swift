import CryptoKit
import XCTest
@testable import RoundWhiteDiscKit

/// Synthetic credentials generated at test time. Nothing here is a real Abbott
/// or Lingo key; nothing is written to disk.
enum T02Fixtures {
    struct Identity {
        let privateKey: P256.KeyAgreement.PrivateKey
        let certificate: Data
    }

    static func identity() -> Identity {
        let key = P256.KeyAgreement.PrivateKey()
        var cert = [UInt8](repeating: 0, count: PhoneCert.totalSize)
        cert[0] = 0x03
        cert[1] = 0x01
        cert.replaceSubrange(PhoneCert.pubkeyRange, with: key.publicKey.x963Representation)
        return Identity(privateKey: key, certificate: Data(cert))
    }

    /// 140-byte sensor certificate whose payload is signed by `signer`.
    static func sensorCert(signedBy signer: P256.Signing.PrivateKey) throws -> Data {
        var payload = Data(repeating: 0x5a, count: SensorCert.headerRange.count)
        payload.append(P256.KeyAgreement.PrivateKey().publicKey.x963Representation)
        let signature = try signer.signature(for: payload).rawRepresentation
        return payload + signature
    }

    static func entryJSON(
        label: String,
        identity: Identity,
        productTypes: [Int]? = nil,
        securityVersions: [Int]? = nil,
        signingKeyHex: String? = nil
    ) -> String {
        var fields = [
            #""label":"\#(label)""#,
            #""privateKeyHex":"\#(identity.privateKey.rawRepresentation.t02Hex)""#,
            #""certificateHex":"\#(identity.certificate.t02Hex)""#,
        ]
        if let productTypes {
            fields.append(#""productTypes":[\#(productTypes.map(String.init).joined(separator: ","))]"#)
        }
        if let securityVersions {
            fields.append(#""securityVersions":[\#(securityVersions.map(String.init).joined(separator: ","))]"#)
        }
        if let signingKeyHex {
            fields.append(#""patchSigningPublicKeyHex":"\#(signingKeyHex)""#)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func fileJSON(_ entries: [String]) -> Data {
        Data(#"{"format":1,"curve":"P-256","identities":[\#(entries.joined(separator: ","))]}"#.utf8)
    }
}

final class LingoIdentityTests: XCTestCase {
    private let lingoSigner = P256.Signing.PrivateKey()
    private let libre3ExtraSigner = P256.Signing.PrivateKey()

    private func parsedIdentities() throws -> [AppIdentity] {
        try AppIdentities.parse(json: T02Fixtures.fileJSON([
            T02Fixtures.entryJSON(label: "legacy-libre3", identity: T02Fixtures.identity()),
            T02Fixtures.entryJSON(
                label: "libre3-extra",
                identity: T02Fixtures.identity(),
                productTypes: [4],
                signingKeyHex: libre3ExtraSigner.publicKey.x963Representation.t02Hex
            ),
            T02Fixtures.entryJSON(
                label: "lingo-synthetic",
                identity: T02Fixtures.identity(),
                productTypes: [9],
                securityVersions: [3],
                signingKeyHex: lingoSigner.publicKey.x963Representation.t02Hex
            ),
        ]))
    }

    func testJSONWithProductTypesParsesAndSelectsByFamily() throws {
        let identities = try parsedIdentities()
        XCTAssertEqual(identities.count, 3)

        let lingo = try XCTUnwrap(AppIdentities.identity(for: .lingo, in: identities))
        XCTAssertEqual(lingo.label, "lingo-synthetic")
        XCTAssertEqual(lingo.productTypes, [9])
        XCTAssertEqual(lingo.securityVersions, [3])
        XCTAssertEqual(lingo.patchSigningPublicKey, lingoSigner.publicKey.x963Representation)

        // Identity without productTypes counts for Libre 3 only, and comes first.
        XCTAssertEqual(AppIdentities.identity(for: .libre3, in: identities)?.label, "legacy-libre3")
        XCTAssertNil(AppIdentities.identity(for: .unknown, in: identities))
    }

    func testInstalledIdentitySelectionByFamily() throws {
        AppIdentities.install(try parsedIdentities())
        XCTAssertEqual(try AppIdentities.identity(for: .lingo)?.label, "lingo-synthetic")
        XCTAssertEqual(try AppIdentities.identity(for: .libre3)?.label, "legacy-libre3")
    }

    func testLegacyIdentityNeverServesLingo() throws {
        let identities = try AppIdentities.parse(json: T02Fixtures.fileJSON([
            T02Fixtures.entryJSON(label: "legacy", identity: T02Fixtures.identity()),
        ]))
        XCTAssertNil(identities[0].productTypes)
        XCTAssertNil(identities[0].patchSigningPublicKey)
        XCTAssertNil(AppIdentities.identity(for: .lingo, in: identities))
        XCTAssertEqual(PatchSigningKeys.keys(for: .lingo, identities: identities), [])
    }

    func testSigningKeyNotOnCurveIsRejected() {
        // Right length and prefix, but (1, 1) is not a point on P-256.
        var offCurve = Data([0x04])
        offCurve.append(Data(repeating: 0, count: 31) + Data([1]))
        offCurve.append(Data(repeating: 0, count: 31) + Data([1]))
        XCTAssertEqual(offCurve.count, 65)
        let json = T02Fixtures.fileJSON([
            T02Fixtures.entryJSON(label: "bad-key", identity: T02Fixtures.identity(), productTypes: [9], signingKeyHex: offCurve.t02Hex),
        ])
        XCTAssertThrowsError(try AppIdentities.parse(json: json)) { error in
            XCTAssertEqual(error as? AppIdentityError, .invalidPatchSigningPublicKey("bad-key"))
        }
    }

    func testSigningKeyWithWrongLengthOrPrefixIsRejected() {
        let valid = lingoSigner.publicKey.x963Representation
        for bad in [valid.prefix(64), Data([0x02]) + valid.dropFirst(), valid.dropFirst()] {
            let json = T02Fixtures.fileJSON([
                T02Fixtures.entryJSON(label: "bad", identity: T02Fixtures.identity(), productTypes: [9], signingKeyHex: Data(bad).t02Hex),
            ])
            XCTAssertThrowsError(try AppIdentities.parse(json: json)) { error in
                XCTAssertEqual(error as? AppIdentityError, .invalidPatchSigningPublicKey("bad"))
            }
        }
    }

    func testOutOfRangeProductTypeIsRejected() {
        let json = T02Fixtures.fileJSON([
            T02Fixtures.entryJSON(label: "bad-pt", identity: T02Fixtures.identity(), productTypes: [300]),
        ])
        XCTAssertThrowsError(try AppIdentities.parse(json: json)) { error in
            XCTAssertEqual(error as? AppIdentityError, .invalidProductTypes("bad-pt"))
        }
    }

    func testLingoKeysNeverIncludeLibre3BundledKeys() throws {
        let identities = try parsedIdentities()
        let lingoKeys = PatchSigningKeys.keys(for: .lingo, identities: identities)
        XCTAssertEqual(lingoKeys, [lingoSigner.publicKey.x963Representation])
        XCTAssertFalse(lingoKeys.contains(Libre3PatchSigningKey.level0))
        XCTAssertFalse(lingoKeys.contains(Libre3PatchSigningKey.level1))
        XCTAssertFalse(lingoKeys.contains(libre3ExtraSigner.publicKey.x963Representation))
    }

    func testLibre3KeysAreBundledPlusDeclaredLibre3Keys() throws {
        let identities = try parsedIdentities()
        let keys = PatchSigningKeys.keys(for: .libre3, identities: identities)
        XCTAssertEqual(keys, Libre3PatchSigningKey.known + [libre3ExtraSigner.publicKey.x963Representation])
        XCTAssertFalse(keys.contains(lingoSigner.publicKey.x963Representation))
        XCTAssertEqual(PatchSigningKeys.keys(for: .libre3, identities: []), Libre3PatchSigningKey.known)
    }

    func testUnknownFamilyHasNoKeys() throws {
        XCTAssertEqual(PatchSigningKeys.keys(for: .unknown, identities: try parsedIdentities()), [])
    }

    func testSensorCertSignedBySyntheticLingoKeyVerifiesOnlyWithLingoKeys() throws {
        let identities = try parsedIdentities()
        let cert = try SensorCert(raw: T02Fixtures.sensorCert(signedBy: lingoSigner))
        XCTAssertEqual(try cert.verifiedSigningKeyIndex(in: PatchSigningKeys.keys(for: .lingo, identities: identities)), 0)
        XCTAssertNil(try cert.verifiedSigningKeyIndex(in: PatchSigningKeys.keys(for: .libre3, identities: identities)))
        XCTAssertNil(try cert.verifiedSigningKeyIndex(in: []))
    }

    func testDirectInitValidatesSigningKey() throws {
        let fixture = T02Fixtures.identity()
        XCTAssertThrowsError(
            try AppIdentity(
                label: "direct",
                privateKey: fixture.privateKey,
                certificate: PhoneCert(raw: fixture.certificate),
                productTypes: [9],
                patchSigningPublicKey: Data(repeating: 0x04, count: 65)
            )
        ) { error in
            XCTAssertEqual(error as? AppIdentityError, .invalidPatchSigningPublicKey("direct"))
        }
    }
}
