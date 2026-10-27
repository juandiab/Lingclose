import Foundation
import LingoCore
import RoundWhiteDiscKit
import Testing
@testable import LingoScan

/// T-08: máquina de estados sobre el sensor sintético y el enlace guionado.
struct SessionCoordinatorTests {
    @Test func happyPairingReachesWarmingUpAndPersistsEachStepBeforeTheNext() async throws {
        let h = try await CoordinatorHarness()
        let stateAtNFC = ValueBox<ActivationState>()
        let stateAtBLE = ValueBox<ActivationState>()
        let pinAtBLE = ValueBox<Bool>()
        let pairing = h.pairing
        await h.nfc.setOnActivate {
            if let id = await pairing.currentSessionID() {
                await stateAtNFC.set(await pairing.loadState(sessionID: id)?.activation.state ?? .failed)
            }
        }
        await h.link.setOnConnect {
            if let id = await pairing.currentSessionID() {
                await stateAtBLE.set(await pairing.loadState(sessionID: id)?.activation.state ?? .failed)
                await pinAtBLE.set(await pairing.loadSecrets(sessionID: id).pin?.count == 4)
            }
        }

        let prepared = try await h.pairUntilSubscribed()
        try await h.emitPatchStatus(currentLifeCount: 10)
        #expect(await eventually { await h.state == .warmingUp(remainingMinutes: 50) })

        // sent antes de NFC; response_saved (con PIN) antes de BLE.
        #expect(await stateAtNFC.value == .sent)
        #expect(await stateAtBLE.value == .responseSaved)
        #expect(await pinAtBLE.value == true)

        let saved = try #require(await h.pairing.loadState(sessionID: prepared.sessionID))
        #expect(saved.activation.state == .authenticated)
        #expect(saved.activation.sequence == 4)
        #expect(saved.identityLabel == "synthetic-lingo")
        #expect(saved.peripheralUUID == h.link.peripheralID)
        let secrets = await h.pairing.loadSecrets(sessionID: prepared.sessionID)
        #expect(secrets.receiverID == 0x1234_5678)
        #expect(secrets.kAuth == (await h.sensor.acceptedKAuth))
        #expect(await h.hook.states == [.prepared, .responseSaved, .authenticated])
        #expect(try await h.store.session(byID: prepared.sessionID)?.activationState == .authenticated)

        let history = await h.history
        #expect(history.contains(.activating))
        #expect(history.contains(.pairing(.subscribing)))

        // Ningún log lleva kAuth ni PIN en hex.
        let kAuthHex = try #require(secrets.kAuth).lowercaseHex
        let pinHex = try #require(secrets.pin).lowercaseHex
        let logs = try await h.store.recentLogEvents(limit: 500).map(\.message)
        #expect(!logs.contains { $0.contains(kAuthHex) || $0.contains(pinHex) })
        #expect(logs.contains { $0.contains("‹secreto 16 B›") })
    }

    @Test func cutAfterCertificateLoadDoneIsInterruptedWithoutCredentialRetry() async throws {
        let h = try await CoordinatorHarness(sensor: SyntheticLingoSensor(behaviour: .dropAfterCertificateLoadDone))
        let prepared = try await h.activate()

        #expect(await eventually {
            if case .authenticationFailed = await h.state { return true }
            return false
        })
        guard case .authenticationFailed(let phase, let reason) = await h.state,
              case .interrupted(let evidence) = reason else {
            Issue.record("estado inesperado: \(await h.state.logLabel)")
            return
        }
        #expect(phase == .certificateAcceptance)
        #expect(evidence.lastCommandSent == 0x03)

        // Sin reintento: una sola conexión y un solo 0x01 aunque pase el tiempo.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await h.link.connectCount == 1)
        #expect(await h.sensor.count(of: 0x01) == 1)
        let saved = try #require(await h.pairing.loadState(sessionID: prepared.sessionID))
        #expect(saved.activation.state == .responseSaved)
        #expect(saved.authFailurePhase == .certificateAcceptance)

        let logs = try await h.store.recentLogEvents(limit: 200).map(\.message)
        #expect(logs.contains { $0.contains("interrumpida en certificateAcceptance") && $0.contains("0x03") && $0.contains("No es un rechazo de credenciales") })

        // Un relanzamiento tampoco vuelve a emparejar solo.
        let relaunched = SensorSessionCoordinator(
            link: h.link, nfc: h.nfc, pairingStore: h.pairing, credentials: h.credentials, store: h.store, clock: h.clock
        )
        await relaunched.start()
        #expect(await relaunched.state == .authenticationFailed(.certificateAcceptance, reason: .other(reason.summary)))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await h.link.connectCount == 1)
    }

    @Test func fragmentedFrameIsStoredAsLiveWithEligibility() async throws {
        let h = try await CoordinatorHarness()
        let prepared = try await h.pairUntilSubscribed()
        try await h.emitPatchStatus(currentLifeCount: 5)
        #expect(await eventually { await h.state == .warmingUp(remainingMinutes: 55) })

        // Calentamiento: se guarda excluida por warm_up.
        try await h.emitRealtime(LingoTestFrames.realtime(lifeCount: 5, mgdl: 110))
        #expect(await eventually { (try? await h.store.reading(recordID: RecordID.make(sessionID: prepared.sessionID, lifeCount: 5))) != nil })
        let warm = try #require(try await h.store.reading(recordID: RecordID.make(sessionID: prepared.sessionID, lifeCount: 5)))
        #expect(warm.origin == .live)
        #expect(warm.eligibility.reason == .warmUp)
        #expect(warm.value == nil)

        // Trama de 57 B en 20 + 20 + 17 tras el calentamiento → elegible.
        try await h.emitRealtime(LingoTestFrames.realtime(lifeCount: 70, mgdl: 201, historicLifeCount: 65, historicMgdl: 198))
        let liveID = RecordID.make(sessionID: prepared.sessionID, lifeCount: 70)
        #expect(await eventually { (try? await h.store.reading(recordID: liveID)) != nil })
        let live = try #require(try await h.store.reading(recordID: liveID))
        #expect(live.origin == .live)
        #expect(live.eligibility.isEligible)
        #expect(live.value == 201)
        #expect(live.raw.uncapped == 201)
        #expect(live.raw.channel == 1)
        #expect(live.raw.trend == 3)
        #expect(live.raw.qualityFlag == false)
        #expect(live.measuredAt == MeasuredAt.compute(activationEpoch: CoordinatorHarness.activationEpoch, lifeCount: 70))

        let embedded = try #require(try await h.store.reading(recordID: RecordID.make(sessionID: prepared.sessionID, lifeCount: 65)))
        #expect(embedded.origin == .embeddedHistory)
        #expect(embedded.value == 198)

        // Bit 15: se guarda excluida por quality_flag, nunca como número.
        try await h.emitRealtime(LingoTestFrames.realtime(lifeCount: 71, mgdl: 150, flagged: true))
        let flaggedID = RecordID.make(sessionID: prepared.sessionID, lifeCount: 71)
        #expect(await eventually { (try? await h.store.reading(recordID: flaggedID)) != nil })
        let flagged = try #require(try await h.store.reading(recordID: flaggedID))
        #expect(flagged.eligibility.reason == .qualityFlag)
        #expect(flagged.value == nil)

        guard case .streaming(let last) = await h.state else {
            Issue.record("se esperaba streaming: \(await h.state.logLabel)")
            return
        }
        #expect(last.lifeCount == 71)
        #expect(await h.coordinator.unexpectedRawCount == 0)
    }

    @Test func fiveMinutesWithoutFramesGoesStaleAndReconnects() async throws {
        let h = try await CoordinatorHarness()
        try await h.pairUntilSubscribed()
        try await h.emitPatchStatus(currentLifeCount: 80)
        try await h.emitRealtime(LingoTestFrames.realtime(lifeCount: 80, mgdl: 120))
        #expect(await eventually {
            if case .streaming = await h.state { return true }
            return false
        })
        let lastFrame = h.clock.now

        h.clock.advance(by: .seconds(299))
        await h.coordinator.evaluateStaleness()
        if case .stale = await h.state { Issue.record("stale antes de 5 min") }

        h.clock.advance(by: .seconds(2))
        await h.coordinator.evaluateStaleness()
        #expect(await h.history.contains(.stale(since: lastFrame)))
        // Se fuerza la desconexión y se reconecta con el handshake corto.
        #expect(await eventually {
            let connects = await h.link.connectCount
            let subscriptions = await h.link.subscribeCount
            return connects == 2 && subscriptions == 2
        })
        #expect(await h.history.contains(.reconnecting(attempt: 1)))
        #expect(await h.sensor.count(of: 0x01) == 1)
    }

    @Test func rejectedShortReconnectFallsBackToFullHandshake() async throws {
        let h = try await CoordinatorHarness()
        let prepared = try await h.pairUntilSubscribed()
        let firstKAuth = await h.pairing.loadSecrets(sessionID: prepared.sessionID).kAuth

        await h.sensor.rejectNextCachedHandshake()
        await h.link.dropLink()

        #expect(await eventually { await h.link.subscribeCount == 2 })
        #expect(await h.link.connectCount == 3)
        #expect(await h.sensor.count(of: 0x11) == 3)
        #expect(await h.sensor.count(of: 0x01) == 2)
        let secondKAuth = await h.pairing.loadSecrets(sessionID: prepared.sessionID).kAuth
        #expect(secondKAuth != nil)
        #expect(secondKAuth != firstKAuth)
        #expect(secondKAuth == (await h.sensor.acceptedKAuth))
        let saved = try #require(await h.pairing.loadState(sessionID: prepared.sessionID))
        #expect(saved.activation.state == .authenticated)
        #expect(saved.activation.sequence == 5)
        #expect(await h.hook.states == [.prepared, .responseSaved, .authenticated, .authenticated])
        let logs = try await h.store.recentLogEvents(limit: 300).map(\.message)
        #expect(logs.contains { $0.contains("handshake corto rechazado") })
    }

    @Test func restorationWithSavedPairingStateReconnects() async throws {
        let sessionID = UUID().uuidString.lowercased()
        let peripheral = UUID()
        let hook = RecordingRecoveryHook()
        let pairing = InMemoryPairingStateStore(recoveryHook: hook)
        let sensor = SyntheticLingoSensor()
        let kAuth = Data((0..<16).map { UInt8($0 * 7) })
        await sensor.setAcceptedKAuth(kAuth)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var record = ActivationRecord.prepared(sessionID: sessionID, attemptID: UUID().uuidString.lowercased(), now: now)
        for next: ActivationState in [.sent, .responseSaved, .authenticated] {
            record = try record.advancing(to: next, now: now)
        }
        var saved = PairingState(activation: record, profile: CoordinatorHarness.profile)
        saved.peripheralUUID = peripheral
        saved.activationTimeEpochS = CoordinatorHarness.activationEpoch
        saved.lastLifeCount = 500
        await pairing.saveState(saved)
        await pairing.saveSecrets(PairingSecrets(
            receiverID: 42, pin: Data([0xC1, 0xC2, 0xC3, 0xC4]), kAuth: kAuth, serial: CoordinatorHarness.serial
        ), sessionID: sessionID)

        let h = try await CoordinatorHarness(sensor: sensor, restored: [peripheral], pairing: pairing, hook: hook)
        await h.coordinator.start()
        #expect(await h.history.first == .reconnecting(attempt: 1))

        #expect(await eventually { await h.link.subscribeCount == 1 })
        #expect(await h.link.connectRequests.first == peripheral)
        #expect(await h.sensor.count(of: 0x01) == 0)
        #expect(await h.sensor.count(of: 0x11) == 1)
        #expect(await h.nfc.activateCount == 0)
        #expect(await h.nfc.readCount == 0)

        // Backfill tras patchStatus, cifrado con el contador saliente desde 1.
        try await h.emitPatchStatus(currentLifeCount: 600)
        #expect(await eventually { await h.link.patchControlWrites.count == 2 })
        let writes = await h.link.patchControlWrites
        #expect(writes.map { $0.suffix(2) } == [Data([0x01, 0x00]), Data([0x02, 0x00])])
        let historic = try await h.sensor.decryptPatchControl(writes[0])
        let clinical = try await h.sensor.decryptPatchControl(writes[1])
        #expect(historic.prefix(3) == Data([0x01, 0x02, 0x01]))
        #expect(clinical == Data([0x01, 0x03, 0x01, 0xF5, 0x01, 0x00, 0x00]))
    }

    @Test func deathBetweenSentAndResponseSavedNeverReactivates() async throws {
        let hook = RecordingRecoveryHook()
        let pairing = InMemoryPairingStateStore(recoveryHook: hook)
        let store = try SQLiteStore(path: FileManager.default.temporaryDirectory.appending(path: "t08-\(UUID().uuidString).sqlite").path(percentEncoded: false))
        let dying = try await CoordinatorHarness(pairing: pairing, hook: hook, store: store, hangOnActivate: true)
        let sentAtNFC = ValueBox<ActivationState>()
        await dying.nfc.setOnActivate {
            if let id = await pairing.currentSessionID() {
                await sentAtNFC.set(await pairing.loadState(sessionID: id)?.activation.state ?? .failed)
            }
        }
        try await dying.coordinator.identify()
        let prepared = try await dying.coordinator.prepareActivation(for: CoordinatorHarness.profile)
        let ticket = try await ActivationTicketFactory.issue(
            profile: CoordinatorHarness.profile, sessionID: prepared.sessionID, confirmationID: UUID(), store: pairing
        )
        // La escritura NFC queda en curso y la app "muere" (el coordinador se abandona).
        let coordinator = dying.coordinator
        Task { try? await coordinator.activate(ticket: ticket) }
        #expect(await eventually { await dying.nfc.activateCount == 1 })
        #expect(await sentAtNFC.value == .sent)

        let relaunched = try await CoordinatorHarness(pairing: pairing, hook: hook, store: store)
        await relaunched.coordinator.start()
        #expect(await relaunched.state == .authenticationFailed(.activation, reason: .incompleteActivation(.sent)))
        try await Task.sleep(for: .milliseconds(200))
        #expect(await relaunched.nfc.activateCount == 0)
        #expect(await relaunched.link.connectCount == 0)
        #expect(await pairing.loadState(sessionID: prepared.sessionID)?.activation.state == .sent)
        #expect(await pairing.loadSecrets(sessionID: prepared.sessionID).receiverID == 0x1234_5678)
        #expect(await hook.states == [.prepared])
        // Un 0xA1 de diagnóstico sigue permitido y no cambia el registro.
        _ = try await relaunched.coordinator.identify()
        #expect(await relaunched.nfc.activateCount == 0)
    }

    @Test func emptySigningKeysAreRejectedBeforeConnecting() async throws {
        let h = try await CoordinatorHarness(signingKeys: [])
        try await h.activate()
        #expect(await eventually { await h.state == .authenticationFailed(.certificateLoad, reason: .noTrustedKeys) })
        #expect(await h.link.connectCount == 0)
    }

    @Test func pauseStopsReconnectionAndSurvivesRelaunch() async throws {
        let h = try await CoordinatorHarness()
        try await h.pairUntilSubscribed()
        await h.coordinator.pause()
        #expect(await h.state == .paused)
        #expect(await h.state.allowsHealthExport == false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await h.link.connectCount == 1)

        let relaunched = SensorSessionCoordinator(
            link: h.link, nfc: h.nfc, pairingStore: h.pairing, credentials: h.credentials, store: h.store, clock: h.clock
        )
        await relaunched.start()
        #expect(await relaunched.state == .paused)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await h.link.connectCount == 1)
    }

    @Test func patchStateAboveFourEndsTheSession() async throws {
        let h = try await CoordinatorHarness()
        let prepared = try await h.pairUntilSubscribed()
        try await h.emitPatchStatus(currentLifeCount: 900, patchState: 6)
        #expect(await eventually { await h.state == .ended(reason: .terminated) })
        #expect(try await h.store.session(byID: prepared.sessionID)?.endReason == .terminated)
    }
}
