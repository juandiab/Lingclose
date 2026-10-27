import CryptoKit
import Foundation
import RoundWhiteDiscKit
import Testing
@testable import LingoScan

/// Serializado: comparten el Keychain del simulador y `AppIdentities` global.
@Suite(.serialized)
struct CredentialStoreTests {
    private let keychain = KeychainItem(service: "com.otalvaro.lingoscan.identity.tests", account: "identity-json")

    private func makeStore() -> CredentialStore { CredentialStore(keychain: keychain) }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// Certificado sintético de 162 B: cabecera 03 01, clave pública en 33..<98
    /// (con prefijo 04), firma de 64 B inventada.
    private func syntheticJSON(label: String = "synthetic", withSigningKey: Bool = true) -> Data {
        let scalar = P256.Signing.PrivateKey().rawRepresentation
        let pub = try! P256.KeyAgreement.PrivateKey(rawRepresentation: scalar).publicKey.x963Representation
        var cert = Data([0x03, 0x01])
        cert.append(Data(repeating: 0xAA, count: 31))
        cert.append(pub)
        cert.append(Data(repeating: 0xBB, count: 64))
        precondition(cert.count == 162)
        var entry: [String: Any] = [
            "label": label,
            "productTypes": [9],
            "securityVersions": [3],
            "privateKeyHex": hex(scalar),
            "certificateHex": hex(cert)
        ]
        if withSigningKey {
            entry["patchSigningPublicKeyHex"] = hex(P256.Signing.PrivateKey().publicKey.x963Representation)
        }
        let root: [String: Any] = ["format": 1, "curve": "P-256", "identities": [entry]]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    private func tempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    @Test func importFromURLInstallsStoresAndKeepsSource() async throws {
        defer { try? keychain.delete() }
        let store = makeStore()
        let url = try tempFile(syntheticJSON())
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.importIdentity(from: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try await store.identity(for: .lingo).label == "synthetic")
        #expect(try await store.signingKeys(for: .lingo).count == 1)
        #expect(try keychain.read() != nil)
    }

    @Test func loadFromKeychainRestoresIdentity() async throws {
        defer { try? keychain.delete() }
        try await makeStore().importIdentity(json: syntheticJSON(label: "persisted"))
        AppIdentities.install([])

        let fresh = makeStore()
        #expect(try await fresh.loadFromKeychain())
        #expect(try await fresh.identity(for: .lingo).label == "persisted")
    }

    @Test func invalidJSONThrowsTypedErrorAndStoresNothing() async throws {
        defer { try? keychain.delete() }
        let store = makeStore()
        await #expect(throws: CredentialImportError.invalidJSON) {
            try await store.importIdentity(json: Data("no es json".utf8))
        }
        #expect(try keychain.read() == nil)

        let mismatched = String(decoding: syntheticJSON(), as: UTF8.self)
            .replacingOccurrences(of: "\"P-256\"", with: "\"P-384\"")
        await #expect(throws: CredentialImportError.unsupportedFormat) {
            try await store.importIdentity(json: Data(mismatched.utf8))
        }
    }

    @Test func keyCertificateMismatchIsRejected() async throws {
        defer { try? keychain.delete() }
        var root = try #require(JSONSerialization.jsonObject(with: syntheticJSON()) as? [String: Any])
        var entries = try #require(root["identities"] as? [[String: Any]])
        entries[0]["privateKeyHex"] = hex(P256.Signing.PrivateKey().rawRepresentation)
        root["identities"] = entries
        let json = try JSONSerialization.data(withJSONObject: root)
        await #expect(throws: CredentialImportError.keyCertificateMismatch) {
            try await makeStore().importIdentity(json: json)
        }
    }

    @Test func secondImportReplacesFirst() async throws {
        defer { try? keychain.delete() }
        let store = makeStore()
        try await store.importIdentity(json: syntheticJSON(label: "first"))
        try await store.importIdentity(json: syntheticJSON(label: "second"))

        #expect(try await store.identity(for: .lingo).label == "second")
        let stored = try #require(try keychain.read())
        #expect(String(decoding: stored, as: UTF8.self).contains("second"))
    }

    @Test func failedImportKeepsPreviousIdentity() async throws {
        defer { try? keychain.delete() }
        let store = makeStore()
        try await store.importIdentity(json: syntheticJSON(label: "keep"))
        await #expect(throws: CredentialImportError.self) {
            try await store.importIdentity(json: Data("{}".utf8))
        }
        #expect(try await store.identity(for: .lingo).label == "keep")
    }

    @Test func signingKeysWithoutDeclaredKeyThrows() async throws {
        defer { try? keychain.delete() }
        let store = makeStore()
        try await store.importIdentity(json: syntheticJSON(withSigningKey: false))
        await #expect(throws: CredentialImportError.noSigningKeys(family: "lingo")) {
            try await store.signingKeys(for: .lingo)
        }
        await #expect(throws: CredentialImportError.noSigningKeys(family: "unknown")) {
            try await store.signingKeys(for: .unknown)
        }
    }

    @Test func missingIdentityThrows() async throws {
        defer { try? keychain.delete() }
        let store = makeStore()
        try await store.importIdentity(json: syntheticJSON())
        await #expect(throws: CredentialImportError.noIdentity(family: "libre3")) {
            try await store.identity(for: .libre3)
        }
    }

    @Test func errorDescriptionsDoNotLeakContent() {
        let errors: [CredentialImportError] = [
            .invalidJSON, .invalidHex(field: "privateKeyHex"), .keyCertificateMismatch,
            .invalidPatchSigningPublicKey, .noSigningKeys(family: "lingo")
        ]
        for error in errors {
            #expect(error.description.hasPrefix("campo:") || error.description.hasPrefix("sin "))
        }
    }
}
