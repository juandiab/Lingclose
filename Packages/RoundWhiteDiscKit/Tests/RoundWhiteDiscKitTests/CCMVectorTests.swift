import XCTest
@testable import RoundWhiteDiscKit

/// Vectores AES-CCM generados con Python `cryptography` (Fixtures/tools/gen_ccm_vectors.py).
/// El JSON se carga por ruta relativa a #filePath (ver load()).
final class CCMVectorTests: XCTestCase {

    private struct Profile: Decodable { let nonce_length: Int; let L: Int; let M: Int }
    private struct Vector: Decodable {
        let id: String
        let key_hex: String
        let nonce_hex: String
        let aad_hex: String?
        let plaintext_hex: String
        let ciphertext_hex: String
        let tag_hex: String
        let expect: String
        let mutation: String?
    }
    private struct File: Decodable {
        let profiles: [String: Profile]
        let vectors: [String: [Vector]]
        let reference_vectors: [Vector]
    }

    private func load() throws -> File {
        // El JSON vive junto al test (Tests/RoundWhiteDiscKitTests/Fixtures/); sin `resources` en el
        // target de tests para no generar un Bundle.module que tape el del paquete (LocalizationTests).
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ccm_vectors.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    private func hex(_ s: String) throws -> Data {
        XCTAssertEqual(s.count % 2, 0)
        var d = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(try XCTUnwrap(UInt8(s[i..<j], radix: 16)))
            i = j
        }
        return d
    }

    private func check(_ v: Vector, nonceLength: Int?) throws {
        let key = try hex(v.key_hex), nonce = try hex(v.nonce_hex)
        let aad = try hex(v.aad_hex ?? "")
        let ct = try hex(v.ciphertext_hex), tag = try hex(v.tag_hex)
        let pt = try hex(v.plaintext_hex)
        if let n = nonceLength { XCTAssertEqual(nonce.count, n, v.id) }
        let aes = AESCCM.commonCryptoBlockEncrypt(key: key)

        switch v.expect {
        case "ok":
            let (gotCT, gotTag) = try AESCCM.encrypt(nonce: nonce, plaintext: pt, aad: aad, tagLength: 4, aes: aes)
            XCTAssertEqual(gotCT, ct, "ciphertext \(v.id)")
            XCTAssertEqual(gotTag, tag, "tag \(v.id)")
            let back = try AESCCM.decrypt(nonce: nonce, ciphertext: ct, tag: tag, aad: aad, aes: aes)
            XCTAssertEqual(back, pt, "roundtrip \(v.id)")
        case "auth_failure":
            XCTAssertThrowsError(try AESCCM.decrypt(nonce: nonce, ciphertext: ct, tag: tag, aad: aad, aes: aes),
                                 "\(v.id) (\(v.mutation ?? "?"))") { e in
                guard let err = e as? AESCCMError, case .macMismatch = err else {
                    return XCTFail("\(v.id): error inesperado \(e)")
                }
            }
        default:
            XCTFail("expect desconocido en \(v.id)")
        }
    }

    func testProfilesAndCounts() throws {
        let f = try load()
        XCTAssertEqual(f.profiles["data_plane"]?.nonce_length, 13)
        XCTAssertEqual(f.profiles["challenge"]?.nonce_length, 7)
        for (name, vs) in f.vectors {
            XCTAssertEqual(vs.filter { $0.expect == "ok" }.count, 20, name)
            XCTAssertEqual(vs.filter { $0.expect == "auth_failure" }.count, 10, name)
        }
    }

    func testPositiveAndNegativeVectorsAllProfiles() throws {
        let f = try load()
        for (name, vs) in f.vectors {
            let n = try XCTUnwrap(f.profiles[name]).nonce_length
            for v in vs { try check(v, nonceLength: n) }
        }
    }

    func testPublicReferenceVectors() throws {
        for v in try load().reference_vectors { try check(v, nonceLength: nil) }
    }
}
