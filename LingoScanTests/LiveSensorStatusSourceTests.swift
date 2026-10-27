import Foundation
import Testing
import LingoCore
@testable import LingoScan

struct LiveSensorStatusSourceTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let profile = CoordinatorHarness.profile

    private func context(_ activation: ActivationState, epoch: Int64? = 1_800_000_000 - 7_200) -> SensorSessionContext {
        var saved = PairingState(
            activation: .prepared(sessionID: "s1", attemptID: "a1", now: Self.now),
            profile: Self.profile
        )
        saved.activationTimeEpochS = epoch
        var context = SensorSessionContext(state: saved, receiverID: 0x1234_ABCD)
        context.activationState = activation
        return context
    }

    @Test func noSensorHasNoProfile() {
        let snapshot = LiveSensorStatusSource.snapshot(for: .noSensor, context: nil, now: Self.now)
        #expect(snapshot == .noSensor)
    }

    @Test func readyToActivateShowsNFCProfileWithRedactedSerial() throws {
        let snapshot = LiveSensorStatusSource.snapshot(
            for: .readyToActivate(Self.profile), context: context(.prepared, epoch: nil), now: Self.now
        )
        #expect(snapshot.state == .readyToActivate)
        let p = try #require(snapshot.profile)
        #expect(p.family == .lingo && p.productType == 9 && p.securityVersion == 3)
        #expect(p.isSupportedVariant)
        #expect(p.serialRedacted == Self.profile.redactedSerial)
        #expect(p.serialRedacted != Self.profile.serialNumber)
        #expect(p.warmupMinutes == 60 && p.wearMinutes == 20_160 && p.stateByte == 1)
        #expect(p.receiverIDPartial == "••••ABCD")
        #expect(!p.synthetic)
    }

    @Test func incompatibleVariantCarriesNote() {
        let libre = SensorProfile(
            family: .libre3, productType: 4, securityVersion: 1, serial: "OTHER0001",
            warmupMinutes: 60, wearMinutes: 20_160, firmwareHex: "00", stateByte: 3
        )
        let snapshot = LiveSensorStatusSource.snapshot(
            for: .incompatible(libre, reason: .unsupportedVariant(productType: 4, securityVersion: 1)),
            context: nil, now: Self.now
        )
        #expect(snapshot.state == .incompatible)
        #expect(snapshot.profile?.isSupportedVariant == false)
        #expect(snapshot.note != nil)
    }

    @Test func authenticationFailedWithIncompleteAttempt() throws {
        let snapshot = LiveSensorStatusSource.snapshot(
            for: .authenticationFailed(.activation, reason: .incompleteActivation(.sent)),
            context: context(.sent), now: Self.now
        )
        #expect(snapshot.state == .authenticationFailed)
        let failure = try #require(snapshot.failure)
        #expect(failure.isIncompleteAttempt)
        #expect(!failure.isInterruption)
        #expect(failure.phase == PairingPhase.activation.displayName)
    }

    @Test func authenticationFailedCertificateIsNotIncomplete() throws {
        let snapshot = LiveSensorStatusSource.snapshot(
            for: .authenticationFailed(.sensorCertificate, reason: .sensorCertificateInvalid),
            context: context(.responseSaved), now: Self.now
        )
        let failure = try #require(snapshot.failure)
        #expect(!failure.isIncompleteAttempt)
        #expect(failure.phase == PairingPhase.sensorCertificate.displayName)
    }

    @Test func pausedKeepsSessionProfile() {
        let snapshot = LiveSensorStatusSource.snapshot(for: .paused, context: context(.authenticated), now: Self.now)
        #expect(snapshot.state == .paused)
        #expect(snapshot.profile?.serialRedacted == Self.profile.redactedSerial)
    }

    @Test func streamingUsesActivationForWarmupAndEnd() throws {
        let summary = ReadingSummary(GlucoseReading(
            sessionID: "s1", lifeCount: 120,
            measuredAt: UTCInstant(Self.now.addingTimeInterval(-60)), receivedAt: UTCInstant(Self.now),
            tzAtCapture: "America/Bogota", origin: .live, value: 100,
            raw: RawReading(capped: 100, uncapped: 100, qualityFlag: false),
            eligibility: LingoScanV1Policy.evaluate(
                raw: RawReading(capped: 100, uncapped: 100, qualityFlag: false),
                lifeCount: 120, warmupMinutes: 60, synthetic: false, deleted: false
            ),
            synthetic: false
        ))
        let snapshot = LiveSensorStatusSource.snapshot(for: .streaming(last: summary), context: context(.authenticated), now: Self.now)
        #expect(snapshot.state == .streaming)
        let p = try #require(snapshot.profile)
        #expect(p.lastConnection == Self.now.addingTimeInterval(-60))
        #expect(p.warmupEndsAt == Self.now.addingTimeInterval(-7_200 + 3_600))
        #expect(p.daysRemaining(at: Self.now) == 14)
    }

    @Test func liveSourceFollowsCoordinator() async throws {
        let harness = try await CoordinatorHarness()
        let source = LiveSensorStatusSource(coordinator: harness.coordinator, pairingStore: harness.pairing)
        #expect(await source.currentStatus().state == .noSensor)
        try await harness.coordinator.identify()
        #expect(await source.currentStatus().state == .readyToActivate)
    }
}
