import Foundation
import LingoCore
import RoundWhiteDiscKit
import Testing
@testable import LingoScan

/// `ActivationTicket` solo sale de la fábrica (init `fileprivate`) y solo para un Lingo v3 sin
/// activar con la sesión en `prepared` y el Receiver ID persistido.
struct ActivationTicketTests {
    private func profile(family: RWDKSensorFamily = .lingo, productType: UInt8 = 9, securityVersion: UInt16 = 3, state: UInt8 = 1) -> SensorProfile {
        SensorProfile(family: family, productType: productType, securityVersion: securityVersion, serial: CoordinatorHarness.serial,
                      warmupMinutes: 60, wearMinutes: 20_160, firmwareHex: "01020304", stateByte: state)
    }

    private func preparedStore(receiverID: UInt32? = 77) async -> (InMemoryPairingStateStore, String) {
        let store = InMemoryPairingStateStore(recoveryHook: RecordingRecoveryHook())
        let id = UUID().uuidString.lowercased()
        let record = ActivationRecord.prepared(sessionID: id, attemptID: UUID().uuidString.lowercased(), now: .now)
        await store.saveState(PairingState(activation: record, profile: profile()))
        await store.saveSecrets(PairingSecrets(receiverID: receiverID, serial: CoordinatorHarness.serial), sessionID: id)
        return (store, id)
    }

    @Test func issuesTicketForFreshLingoWithPersistedReceiverID() async throws {
        let (store, id) = await preparedStore()
        let confirmation = UUID()
        let ticket = try await ActivationTicketFactory.issue(profile: profile(), sessionID: id, confirmationID: confirmation, store: store)
        #expect(ticket.receiverID == 77)
        #expect(ticket.confirmationID == confirmation)
        #expect(ticket.sessionID == id)
    }

    @Test(arguments: [
        (RWDKSensorFamily.libre3, UInt8(4), UInt16(1)),
        (RWDKSensorFamily.unknown, UInt8(9), UInt16(2)),
        (RWDKSensorFamily.unknown, UInt8(7), UInt16(3)),
    ])
    func refusesNonLingo(family: RWDKSensorFamily, productType: UInt8, securityVersion: UInt16) async {
        let (store, id) = await preparedStore()
        await #expect(throws: ActivationTicketError.notLingo) {
            try await ActivationTicketFactory.issue(
                profile: profile(family: family, productType: productType, securityVersion: securityVersion),
                sessionID: id, confirmationID: UUID(), store: store
            )
        }
    }

    @Test(arguments: [UInt8(0), 2, 3, 4, 6, 8])
    func refusesSensorThatIsNotFresh(state: UInt8) async {
        let (store, id) = await preparedStore()
        await #expect(throws: ActivationTicketError.sensorNotFresh(stateByte: state)) {
            try await ActivationTicketFactory.issue(profile: profile(state: state), sessionID: id, confirmationID: UUID(), store: store)
        }
    }

    @Test func refusesWithoutPreparedSessionOrReceiverID() async throws {
        let empty = InMemoryPairingStateStore(recoveryHook: RecordingRecoveryHook())
        await #expect(throws: ActivationTicketError.notPrepared) {
            try await ActivationTicketFactory.issue(profile: profile(), sessionID: "nope", confirmationID: UUID(), store: empty)
        }
        let (noReceiver, id) = await preparedStore(receiverID: nil)
        await #expect(throws: ActivationTicketError.receiverIDNotPersisted) {
            try await ActivationTicketFactory.issue(profile: profile(), sessionID: id, confirmationID: UUID(), store: noReceiver)
        }
        let (sent, sentID) = await preparedStore()
        _ = try await sent.transition(sessionID: sentID, to: .sent, now: .now)
        await #expect(throws: ActivationTicketError.notPrepared) {
            try await ActivationTicketFactory.issue(profile: profile(), sessionID: sentID, confirmationID: UUID(), store: sent)
        }
    }

    @Test func activationRecordOnlyAllowsTheDurableOrder() throws {
        let record = ActivationRecord.prepared(sessionID: "s", attemptID: "a", now: .now)
        #expect(throws: ActivationTransitionError.notAllowed(from: .prepared, to: .responseSaved)) {
            try record.advancing(to: .responseSaved, now: .now)
        }
        let sent = try record.advancing(to: .sent, now: .now)
        #expect(throws: ActivationTransitionError.notAllowed(from: .sent, to: .authenticated)) {
            try sent.advancing(to: .authenticated, now: .now)
        }
        let failed = try sent.advancing(to: .failed, reason: "x", now: .now)
        #expect(failed.failureReason == "x")
        #expect(failed.sequence == 3)
        #expect(throws: ActivationTransitionError.self) { try failed.advancing(to: .sent, now: .now) }
    }
}
