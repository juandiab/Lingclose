import Foundation
import Testing
@testable import LingoCore

/// Round-trip de `RecoveryPayload` contra las cargas en claro del contrato: las 3 válidas de
/// `vectors.json` (`plaintext_json`) y las 3 de `examples/recovery/merge/`. Se compara como JSON
/// canónico (claves ordenadas), así que ninguna clave, `null` explícito ni clave extra se pierde.
@Suite("RecoveryPayload: modelo §3.2 y validación")
struct RecoveryPayloadTests {
    static let recoveryDir = RecoveryCryptoTests.sharedRecovery
    static let mergeFiles = ["payload_seq1_prepared.json", "payload_seq2_response_saved.json", "payload_seq3_authenticated.json"]

    static func canonical(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let out = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        return String(decoding: out, as: UTF8.self)
    }

    static func validPlaintexts() throws -> [(String, Data)] {
        let ids = ["valid_minimal_prepared", "valid_full_no_material", "valid_full_with_material"]
        let vectors = try RecoveryCryptoTests.loadVectors()
        return ids.map { id in (id, Data(vectors.first { $0.id == id }!.plaintext_json.utf8)) }
    }

    static func mergePayloads() throws -> [(String, Data)] {
        try mergeFiles.map { ($0, try Data(contentsOf: recoveryDir.appendingPathComponent("merge/\($0)"))) }
    }

    @Test("round-trip sin pérdida de claves: 3 vectores + 3 cargas de fusión")
    func roundTrip() throws {
        let all = try Self.validPlaintexts() + Self.mergePayloads()
        #expect(all.count == 6)
        for (name, data) in all {
            let payload = try RecoveryPayload.decode(data)
            let again = try payload.encoded()
            #expect(try Self.canonical(again) == Self.canonical(data), "\(name)")
            #expect(try RecoveryPayload.decode(again) == payload, "\(name)")
        }
    }

    @Test("la clave extra _fixture se conserva y material solo con include_material")
    func extrasAndMaterial() throws {
        let (_, seq1) = try Self.mergePayloads()[0]
        let p = try RecoveryPayload.decode(seq1)
        #expect(p.extra["_fixture"] != nil)
        let withMaterial = try RecoveryPayload.decode(Self.validPlaintexts()[2].1)
        #expect(withMaterial.appIdentity.includeMaterial)
        #expect(withMaterial.appIdentity.material != nil)
        #expect(!String(describing: withMaterial.appIdentity.material!).contains(withMaterial.appIdentity.material!.privateKeyHex))
    }

    static func mutate(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func mutateSession(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        try mutate(data) { root in
            var sessions = root["sessions"] as! [[String: Any]]
            change(&sessions[0])
            root["sessions"] = sessions
        }
    }

    @Test("obligatorios no anulables: ausentes o null se rechazan")
    func requiredFields() throws {
        let (_, base) = try Self.mergePayloads()[2]
        for key in ["payload_version", "exported_at_utc", "exported_by_app_id", "receiver_id", "receiver_id_origin", "app_identity", "sessions"] {
            #expect(throws: RecoveryPayloadError.self, "falta \(key)") {
                try RecoveryPayload.decode(try Self.mutate(base) { $0.removeValue(forKey: key) })
            }
            #expect(throws: RecoveryPayloadError.self, "null \(key)") {
                try RecoveryPayload.decode(try Self.mutate(base) { $0[key] = NSNull() })
            }
        }
        for key in ["session_id", "sensor_serial_hash", "attempt_id", "sequence", "updated_at_utc", "activation", "ble", "auth"] {
            #expect(throws: RecoveryPayloadError.self, "null sesión.\(key)") {
                try RecoveryPayload.decode(try Self.mutateSession(base) { $0[key] = NSNull() })
            }
        }
        // Hojas anulables: deben existir como clave, pero pueden ser null.
        _ = try RecoveryPayload.decode(try Self.mutateSession(base) { $0["sensor_serial"] = NSNull() })
        #expect(throws: RecoveryPayloadError.self) {
            try RecoveryPayload.decode(try Self.mutateSession(base) { $0.removeValue(forKey: "sensor_serial") })
        }
        #expect(throws: RecoveryPayloadError.self) {
            try RecoveryPayload.decode(try Self.mutateSession(base) { s in
                var a = s["activation"] as! [String: Any]; a["state"] = NSNull(); s["activation"] = a
            })
        }
    }

    @Test("patrones del esquema y cardinalidades")
    func schemaPatterns() throws {
        let (_, base) = try Self.mergePayloads()[2]
        let bad: [(String, Data)] = [
            ("sessions vacía", try Self.mutate(base) { $0["sessions"] = [Any]() }),
            ("product_types vacía", try Self.mutate(base) { r in
                var a = r["app_identity"] as! [String: Any]; a["product_types"] = [Int](); r["app_identity"] = a }),
            ("material con include false", try Self.mutate(base) { r in
                var a = r["app_identity"] as! [String: Any]
                a["material"] = ["private_key_hex": "00", "certificate_hex": "00", "patch_signing_public_key_hex": "00"]
                r["app_identity"] = a }),
            ("uuid mayúsculas", try Self.mutateSession(base) { $0["session_id"] = "3FA85F64-5717-4562-B3FC-2C963F66AFA6" }),
            ("sequence 0", try Self.mutateSession(base) { $0["sequence"] = 0 }),
            ("fecha sin Z", try Self.mutateSession(base) { $0["updated_at_utc"] = "2026-10-27T12:01:40" }),
            ("pin corto", try Self.mutateSession(base) { s in
                var b = s["ble"] as! [String: Any]; b["pin_hex"] = "0a0b0c"; s["ble"] = b }),
            ("mac minúsculas", try Self.mutateSession(base) { s in
                var b = s["ble"] as! [String: Any]; b["address"] = "aa:bb:cc:dd:ee:ff"; s["ble"] = b }),
            ("respuesta 18 B", try Self.mutateSession(base) { s in
                var a = s["activation"] as! [String: Any]; a["response_hex"] = String(repeating: "ab", count: 18); s["activation"] = a }),
            ("estado desconocido", try Self.mutateSession(base) { s in
                var a = s["activation"] as! [String: Any]; a["state"] = "activated"; s["activation"] = a }),
            ("payload_version 2", try Self.mutate(base) { $0["payload_version"] = 2 }),
        ]
        for (name, data) in bad {
            #expect(throws: RecoveryPayloadError.self, "\(name)") { try RecoveryPayload.decode(data) }
        }
    }

    @Test("los errores no contienen valores secretos")
    func errorsAreRedacted() throws {
        let (_, base) = try Self.mergePayloads()[2]
        let data = try Self.mutateSession(base) { s in
            var b = s["ble"] as! [String: Any]; b["pin_hex"] = "zz0b0c0d"; s["ble"] = b }
        do {
            _ = try RecoveryPayload.decode(data)
            Issue.record("debía fallar")
        } catch {
            #expect(!String(describing: error).contains("zz0b0c0d"))
        }
    }
}
