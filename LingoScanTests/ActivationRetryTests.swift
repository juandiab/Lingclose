import Foundation
import LingoCore
import RoundWhiteDiscKit
import Testing
@testable import LingoScan

/// 27-oct: dos sesiones NFC fallaron con "patchInfo inválido (64 B)" antes del `0xA0` y cada
/// reintento creó una sesión y un Receiver ID nuevos. D-22: Receiver ID por sensor, no por intento.
/// La reconexión corta tras reiniciar con kAuth guardada ya la cubre
/// `SessionCoordinatorTests.restorationWithSavedPairingStateReconnects`.
@Suite(.serialized)
struct ActivationRetryTests {
    static let patch64 = NFCServiceError.invalidPatchInfo(length: 64, head: "12 34 56", a5Offset: 7)

    /// Lectura `0xA1` → `prepared` (o reutilizada) → ticket → `0xA0`, como la hoja de activación.
    @discardableResult
    static func attempt(_ h: CoordinatorHarness) async throws -> PreparedActivation {
        try await h.coordinator.identify()
        let prepared = try await h.coordinator.prepareActivation(for: CoordinatorHarness.profile)
        let ticket = try await ActivationTicketFactory.issue(
            profile: CoordinatorHarness.profile, sessionID: prepared.sessionID, confirmationID: UUID(), store: h.pairing
        )
        try await h.coordinator.activate(ticket: ticket)
        return prepared
    }

    static func isActivationFailure(_ state: SessionState) -> Bool {
        if case .authenticationFailed(.activation, _) = state { return true }
        return false
    }

    @Test func twoFailuresBeforeA0ThenSuccessKeepOneSessionAndOneReceiverID() async throws {
        let hook = LiveRecoveryExportHook()
        let pairing = InMemoryPairingStateStore(recoveryHook: hook)
        let ids = CountingReceiverIDs()
        let h = try await CoordinatorHarness(pairing: pairing, receiverIDGenerator: { ids.next() })
        let dir = try RecoveryServiceTests.tempDir("retry")
        let service = try RecoveryServiceTests.makeService(pairing: pairing, credentials: h.credentials, store: h.store, exportDir: dir)
        try await service.setPassphrase(RecoveryServiceTests.passphrase)
        await hook.attach(service)

        await h.nfc.failNextActivations([Self.patch64, Self.patch64])
        let first = try await Self.attempt(h)
        #expect(Self.isActivationFailure(await h.state))
        let second = try await Self.attempt(h)
        #expect(Self.isActivationFailure(await h.state))
        let third = try await Self.attempt(h)
        #expect(await eventually { await h.link.subscribeCount >= 1 })
        #expect(await eventually { ((try? RecoveryServiceTests.exported(dir).count) ?? 0) == 3 })

        // Una sola sesión, un solo Receiver ID, tres attempt_id.
        #expect(Set([first, second, third].map(\.sessionID)).count == 1)
        #expect(Set([first, second, third].map(\.attemptID)).count == 3)
        #expect(ids.values == [0x0100_0001], "el generador se llama una sola vez")
        #expect([first, second, third].allSatisfy { $0.receiverID == 0x0100_0001 })
        #expect(await h.nfc.receiverIDsSeen == [0x0100_0001, 0x0100_0001, 0x0100_0001])
        #expect(await h.nfc.activateCount == 3)
        #expect(await h.nfc.acceptedCount == 1)

        let rows = try await h.store.sessions(bySerialHash: CoordinatorHarness.profile.serialHash)
        #expect(rows.count == 1, "sin sesiones failed huérfanas en sensor_sessions")
        #expect(rows.first?.activationState == .authenticated)
        let saved = try #require(await pairing.loadState(sessionID: first.sessionID))
        #expect(saved.activation.state == .authenticated)
        #expect(saved.activation.attemptID == third.attemptID)
        // prepared 1, sent 2, failed 3, prepared 4, sent 5, failed 6, prepared 7, sent 8, response_saved 9, authenticated 10.
        #expect(saved.activation.sequence == 10)

        // Recuperación: 1 (prepared, reutilizado), 2 (response_saved), 3 (authenticated).
        let files = try RecoveryServiceTests.exported(dir)
        #expect(files.map { $0.payload.sessions[0].sequence } == [1, 2, 3])
        #expect(files.map { $0.payload.sessions[0].activation.state } == [.prepared, .responseSaved, .authenticated])
        #expect(files.allSatisfy { $0.payload.receiverID == 0x0100_0001 && $0.payload.sessions[0].sessionID == first.sessionID })
        #expect(files[0].payload.sessions[0].attemptID == first.attemptID)
        #expect(files[1].payload.sessions[0].attemptID == third.attemptID)
        #expect(files[2].payload.sessions[0].attemptID == third.attemptID)

        let logs = try await h.store.recentLogEvents(limit: 500).map(\.message)
        #expect(logs.filter { $0.contains("reutilizada tras fallo previo al 0xA0") }.count == 2)
        #expect(logs.contains { $0.contains("patchInfo inválido (64 B; inicio 12 34 56; A5 en 7)") })
    }

    @Test func receiverIDRejectedWithB1GetsANewReceiverID() async throws {
        let ids = CountingReceiverIDs()
        let h = try await CoordinatorHarness(receiverIDGenerator: { ids.next() })
        await h.nfc.failNextActivations([NFCServiceError.activationRejected(code: 0xB1, reason: .receiverIDRejected)])
        let rejected = try await Self.attempt(h)
        #expect(Self.isActivationFailure(await h.state))
        #expect(await h.pairing.loadState(sessionID: rejected.sessionID)?.receiverIDRejected == true)

        let next = try await Self.attempt(h)
        #expect(next.sessionID != rejected.sessionID)
        #expect(next.receiverID != rejected.receiverID)
        #expect(ids.values == [0x0100_0001, 0x0100_0002])
        #expect(await h.nfc.receiverIDsSeen == [0x0100_0001, 0x0100_0002])
    }

    @Test func failureWithSavedResponseIsNeverReused() async throws {
        let ids = CountingReceiverIDs()
        let h = try await CoordinatorHarness(receiverIDGenerator: { ids.next() })
        await h.nfc.failNextActivations([Self.patch64])
        let failed = try await Self.attempt(h)
        // Simula un fallo posterior a que el sensor aceptara: hay respuesta guardada.
        await h.pairing.saveSecrets(PairingSecrets(activationResponse: Data([0x00, 0xA5, 0x00])), sessionID: failed.sessionID)

        let next = try await Self.attempt(h)
        #expect(next.sessionID != failed.sessionID)
        #expect(ids.values.count == 2)
    }

    @Test func cancelledSheetReusesPreparedSessionAndAttempt() async throws {
        let ids = CountingReceiverIDs()
        let h = try await CoordinatorHarness(receiverIDGenerator: { ids.next() })
        try await h.coordinator.identify()
        let first = try await h.coordinator.prepareActivation(for: CoordinatorHarness.profile)
        try await h.coordinator.identify()
        let again = try await h.coordinator.prepareActivation(for: CoordinatorHarness.profile)
        #expect(again == first)
        #expect(ids.values.count == 1)
        #expect(await h.hook.states == [.prepared], "reutilizar no vuelve a exportar")
        #expect(await h.nfc.activateCount == 0)
    }

    /// Puente fork → app: la trama extraída de 64 B da el mismo perfil que la directa y el error
    /// de 64 B basura no lleva el serial.
    @Test func sixtyFourBytePatchInfoMapsToTheSameProfile() throws {
        var body: [UInt8] = [0x03, 0x00, 0x08, 0x00, 0x01, 0x00, 0xC0, 0x4E, 0x01, 0x02, 0x03, 0x04, 0x09, 0x0C, 0x01]
        body += Array(CoordinatorHarness.serial.utf8)
        let crc = NFCActivationCommand.abbottCRC16(Data(body))
        let frame = Data([0x00, 0xA5, 0x00] + body + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
        var long = Data([0x12, 0x34, 0x56, 0x00]) + frame.dropFirst()
        long += Data(repeating: 0xEE, count: 64 - long.count)

        let direct = SensorProfile(patchInfo: try Libre3NFCPatchInfo(raw: frame))
        let extracted = SensorProfile(patchInfo: try Libre3NFCPatchInfo(raw: long))
        #expect(extracted == direct)
        #expect(extracted.isSupportedLingo && extracted.isFresh)

        var garbage = long
        garbage[20] ^= 0xFF
        #expect(throws: Libre3NFCError.self) { try Libre3NFCPatchInfo(raw: garbage) }
        let mapped = NFCServiceError(Libre3NFCError.invalidPatchInfo(garbage))
        #expect(mapped == .invalidPatchInfo(length: 64, head: "12 34 56", a5Offset: 4))
        #expect(!mapped.description.contains(CoordinatorHarness.serial))
    }
}
