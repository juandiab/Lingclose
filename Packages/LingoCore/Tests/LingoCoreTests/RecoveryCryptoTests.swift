import Foundation
import Testing
@testable import LingoCore

/// Vectores de `LingoScan_Shared/examples/recovery/vectors.json` (contrato draft.3/draft.4, C8):
/// 3 válidos, 4 negativos y 6 de normalización. Se leen por ruta relativa al repositorio hermano
/// `LingoScan_Shared`; si no está, el test falla con un mensaje claro.
@Suite("RecoveryCrypto contra los vectores del contrato")
struct RecoveryCryptoTests {
    struct Vector: Decodable {
        let id: String
        let expect: String
        let passphrase: String
        let salt_b64: String
        let nonce_b64: String
        let aad: String
        let derived_key_hex: String
        let plaintext_json: String
        let ciphertext_b64: String
        let tag_b64: String
        let archive_id: String
        let created_at_utc: String
        let passphrase_normalized_utf8_hex: String?
        let same_key_as_base: Bool?
    }
    struct File: Decodable { let cases: [Vector] }

    static let sharedRecovery: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // LingoCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // LingoCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // LingoScan_Claude
            .deletingLastPathComponent()  // LingoScan (raíz con LingoScan_Shared)
            .appendingPathComponent("LingoScan_Shared/examples/recovery", isDirectory: true)
    }()

    static func loadVectors() throws -> [Vector] {
        let url = sharedRecovery.appendingPathComponent("vectors.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(File.self, from: data).cases
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static let producer = RecoveryEnvelope.Producer(appID: "com.otalvaro.lingoscan", producerTag: "lingoscan", appVersion: "test")

    @Test("normalización de frase: bytes UTF-8 exactos y conjunto de recorte")
    func normalization() throws {
        let vectors = try Self.loadVectors().filter { $0.passphrase_normalized_utf8_hex != nil }
        #expect(vectors.count == 6)
        for v in vectors {
            #expect(Self.hex(RecoveryPassphrase.bytes(v.passphrase)) == v.passphrase_normalized_utf8_hex!, "\(v.id)")
        }
        // U+200B y U+001C se conservan; U+00A0 y U+3000 se recortan; NFD → NFC.
        #expect(RecoveryPassphrase.normalized("\u{200B}x\u{200B}") == "\u{200B}x\u{200B}")
        #expect(RecoveryPassphrase.normalized("\u{1C}x\u{1C}") == "\u{1C}x\u{1C}")
        #expect(RecoveryPassphrase.normalized("\u{A0}x\u{3000}") == "x")
        #expect(RecoveryPassphrase.normalized("cafe\u{0301}") == "caf\u{E9}")
        #expect(RecoveryPassphrase.trimSet.count == 25)
    }

    @Test("clave derivada, apertura y resellado de cada vector")
    func vectors() throws {
        let vectors = try Self.loadVectors()
        #expect(vectors.count == 13)
        let baseKey = vectors.first { $0.id == "norm_nfc_base" }?.derived_key_hex
        for v in vectors {
            let salt = try #require(Data(base64Encoded: v.salt_b64))
            let nonce = try #require(Data(base64Encoded: v.nonce_b64))
            let key = try RecoveryKDF.deriveKey(passphrase: v.passphrase, salt: salt)
            #expect(Self.hex(key) == v.derived_key_hex, "\(v.id): clave derivada")
            if let same = v.same_key_as_base, let baseKey {
                #expect((Self.hex(key) == baseKey) == same, "\(v.id): same_key_as_base")
            }
            let envelope = RecoveryEnvelope(
                format: RecoveryEnvelope.formatName, formatVersion: 1,
                archiveID: v.archive_id, createdAtUTC: v.created_at_utc, producer: Self.producer,
                kdf: .init(name: RecoveryEnvelope.kdfName, iterations: RecoveryKDF.defaultIterations,
                           saltB64: v.salt_b64, keyLength: RecoveryKDF.keyLength),
                cipher: .init(name: RecoveryEnvelope.cipherName, nonceB64: v.nonce_b64),
                aad: v.aad, ciphertextB64: v.ciphertext_b64, tagB64: v.tag_b64)
            switch v.expect {
            case "ok":
                let plain = try RecoveryCrypto.open(envelope, passphrase: v.passphrase)
                #expect(String(decoding: plain, as: UTF8.self) == v.plaintext_json, "\(v.id): texto en claro")
                // Resellar con la misma sal y nonce reproduce ciphertext y tag byte a byte.
                let resealed = try RecoveryCrypto.seal(plaintext: Data(v.plaintext_json.utf8), passphrase: v.passphrase,
                                                       archiveID: v.archive_id, createdAtUTC: v.created_at_utc,
                                                       producer: Self.producer, salt: salt, nonce: nonce)
                #expect(resealed.ciphertextB64 == v.ciphertext_b64, "\(v.id): ciphertext")
                #expect(resealed.tagB64 == v.tag_b64, "\(v.id): tag")
            case "auth_failure":
                // La AAD alterada falla antes en validate() (incoherente con archive_id/created_at) o en el tag;
                // en ambos casos el resultado para el usuario es un error, nunca texto en claro.
                #expect(throws: (any Error).self, "\(v.id)") {
                    _ = try RecoveryCrypto.open(envelope, passphrase: v.passphrase)
                }
            default:
                Issue.record("expect desconocido: \(v.expect)")
            }
        }
    }

    @Test("example.lingoscan-recovery.json se decodifica, valida y abre con la frase de prueba")
    func exampleEnvelope() throws {
        let vectors = try Self.loadVectors()
        let passphrase = try #require(vectors.first { $0.id == "valid_full_no_material" }?.passphrase)
        let data = try Data(contentsOf: Self.sharedRecovery.appendingPathComponent("example.lingoscan-recovery.json"))
        let envelope = try RecoveryEnvelope.decode(data)
        try envelope.validate()
        let plain = try RecoveryCrypto.open(envelope, passphrase: passphrase)
        let obj = try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(obj["payload_version"] as? Int == 1)
        #expect(throws: RecoveryCryptoError.authenticationFailed) {
            _ = try RecoveryCrypto.open(envelope, passphrase: passphrase + "x")
        }
    }

    @Test("sellado aleatorio: round-trip, JSON snake_case y rechazo de versiones futuras")
    func roundTrip() throws {
        let plaintext = Data(#"{"payload_version":1,"hola":"mundo"}"#.utf8)
        let env = try RecoveryCrypto.seal(plaintext: plaintext, passphrase: "  frase-de-prueba-ñ  ",
                                          archiveID: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
                                          createdAtUTC: "2026-10-27T15:10:00Z", producer: Self.producer, iterations: 1_000)
        let json = try env.encoded()
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("\"ciphertext_b64\"") && text.contains("\"format_version\"") && text.contains("\"salt_b64\""))
        let decoded = try RecoveryEnvelope.decode(json)
        #expect(try RecoveryCrypto.open(decoded, passphrase: "frase-de-prueba-ñ") == plaintext)
        var future = decoded
        future.formatVersion = 2
        future.aad = RecoveryEnvelope.aadString(formatVersion: 2, archiveID: future.archiveID, createdAtUTC: future.createdAtUTC)
        #expect(throws: RecoveryCryptoError.unsupportedFormat("format_version 2")) {
            _ = try RecoveryCrypto.open(future, passphrase: "frase-de-prueba-ñ")
        }
    }
}
