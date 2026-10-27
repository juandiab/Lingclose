import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// Almacén real: JSON en un directorio temporal y secretos en un servicio de Keychain de pruebas.
@Suite(.serialized)
struct PairingStateStoreTests {
    @Test func persistsStateSecretsAndTransitionsWithHook() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "t08-pairing-\(UUID().uuidString)")
        let hook = RecordingRecoveryHook()
        let store = PairingStateStore(directory: directory, keychainService: "com.otalvaro.lingoscan.pairing.tests", recoveryHook: hook)
        let id = UUID().uuidString.lowercased()
        defer {
            Task { try? await store.remove(sessionID: id) }
            try? FileManager.default.removeItem(at: directory)
        }

        let state = PairingState(
            activation: .prepared(sessionID: id, attemptID: "attempt", now: Date(timeIntervalSince1970: 1_800_000_000)),
            profile: CoordinatorHarness.profile
        )
        try await store.saveSecrets(PairingSecrets(receiverID: 0xDEAD_BEEF, serial: CoordinatorHarness.serial), sessionID: id)
        try await store.begin(state)
        _ = try await store.transition(sessionID: id, to: .sent, now: .now)
        try await store.saveSecrets(PairingSecrets(pin: Data([1, 2, 3, 4]), bleAddress: "11:22", activationResponse: Data(repeating: 9, count: 19)), sessionID: id)
        _ = try await store.transition(sessionID: id, to: .responseSaved, now: .now)
        try await store.saveSecrets(PairingSecrets(kAuth: Data(repeating: 7, count: 16)), sessionID: id)

        #expect(try await store.currentSessionID() == id)
        let loaded = try #require(try await store.loadState(sessionID: id))
        #expect(loaded.activation.state == .responseSaved)
        #expect(loaded.activation.sequence == 3)
        let secrets = try await store.loadSecrets(sessionID: id)
        #expect(secrets.receiverID == 0xDEAD_BEEF)
        #expect(secrets.pin == Data([1, 2, 3, 4]))
        #expect(secrets.kAuth == Data(repeating: 7, count: 16))
        #expect(secrets.bleAddress == "11:22")
        #expect(secrets.activationResponse?.count == 19)
        #expect(secrets.serial == CoordinatorHarness.serial)
        #expect(await hook.states == [.prepared, .responseSaved])

        // El JSON no contiene secretos ni el serial completo.
        let json = try String(contentsOf: directory.appending(path: "pairing-state-\(id).json"), encoding: .utf8)
        #expect(!json.contains(CoordinatorHarness.serial))
        #expect(!json.contains("07070707"))
        #expect(json.contains("\"attempt_id\""))
        #expect(json.contains("\"sequence\""))
        #expect(json.contains("\"activation_state\" : \"response_saved\""))
        #expect(PairingSecrets(kAuth: Data(repeating: 7, count: 16)).description == "PairingSecrets(‹redactado›)")
    }
}
