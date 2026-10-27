import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Adaptador real: observa `SensorSessionCoordinator` y traduce `SessionState` a
/// `SensorStatusSnapshot`, completando el perfil con la sesión guardada.
struct LiveSensorStatusSource: SensorStatusSource {
    let coordinator: SensorSessionCoordinator
    let pairingStore: any PairingStatePersisting
    var clock: @Sendable () -> Date = { .now }

    func currentStatus() async -> SensorStatusSnapshot {
        await snapshot(for: coordinator.state)
    }

    func statusUpdates() -> AsyncStream<SensorStatusSnapshot> {
        let source = self
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let task = Task {
                for await state in await source.coordinator.states() {
                    continuation.yield(await source.snapshot(for: state))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func snapshot(for state: SessionState) async -> SensorStatusSnapshot {
        Self.snapshot(for: state, context: await loadContext(), now: clock())
    }

    private func loadContext() async -> SensorSessionContext? {
        guard let id = try? await pairingStore.currentSessionID(),
              let saved = try? await pairingStore.loadState(sessionID: id) else { return nil }
        let receiverID = (try? await pairingStore.loadSecrets(sessionID: id))?.receiverID
        return SensorSessionContext(state: saved, receiverID: receiverID)
    }

    // MARK: - Mapeo puro

    static func snapshot(for state: SessionState, context: SensorSessionContext?, now: Date) -> SensorStatusSnapshot {
        switch state {
        case .noSensor:
            return .noSensor
        case .identified(let read):
            return SensorStatusSnapshot(state: .identified, profile: profile(read, context: context))
        case .incompatible(let read, let reason):
            return SensorStatusSnapshot(state: .incompatible, profile: profile(read, context: context), note: note(reason))
        case .readyToActivate(let read):
            return SensorStatusSnapshot(state: .readyToActivate, profile: profile(read, context: context))
        case .activating:
            return SensorStatusSnapshot(state: .activating, profile: profile(context, lastConnection: nil))
        case .pairing:
            return SensorStatusSnapshot(state: .pairing, profile: profile(context, lastConnection: nil))
        case .warmingUp(let remaining):
            var p = profile(context, lastConnection: now)
            if p?.warmupEndsAt == nil { p?.warmupEndsAt = now.addingTimeInterval(Double(remaining) * 60) }
            return SensorStatusSnapshot(state: .warmingUp, profile: p)
        case .streaming(let last):
            return SensorStatusSnapshot(state: .streaming, profile: profile(context, lastConnection: last.measuredAt.date))
        case .stale(let since):
            return SensorStatusSnapshot(state: .stale, profile: profile(context, lastConnection: since))
        case .reconnecting:
            return SensorStatusSnapshot(state: .reconnecting, profile: profile(context, lastConnection: nil))
        case .ended:
            return SensorStatusSnapshot(state: .ended, profile: profile(context, lastConnection: nil))
        case .authenticationFailed(let phase, let reason):
            let incomplete = reason == .incompleteActivation(.sent) || context?.activationState == .sent
            let failure = SensorFailureDetail(
                phase: phase.displayName,
                summary: reason.summary,
                isIncompleteAttempt: incomplete,
                isInterruption: reason.isInterruption
            )
            return SensorStatusSnapshot(state: .authenticationFailed, profile: profile(context, lastConnection: nil), failure: failure)
        case .paused:
            return SensorStatusSnapshot(state: .paused, profile: profile(context, lastConnection: nil))
        }
    }

    /// Perfil de una lectura NFC. El Receiver ID solo si la sesión guardada es de ese sensor.
    private static func profile(_ read: SensorProfile, context: SensorSessionContext?) -> SensorPresentationProfile {
        var p = SensorPresentationProfile(
            family: CoreSensorFamily(rawValue: read.family.rawValue) ?? .unknown,
            productType: Int(read.productType),
            securityVersion: Int(read.securityVersion)
        )
        p.serialRedacted = read.redactedSerial
        p.warmupMinutes = read.warmupMinutes
        p.wearMinutes = read.wearMinutes
        p.stateByte = Int(read.stateByte)
        if let context, context.serialRedacted == read.redactedSerial {
            p.receiverIDPartial = context.receiverIDPartial
        }
        return p
    }

    /// Perfil de la sesión guardada, con calentamiento y fin calculados desde la activación.
    private static func profile(_ context: SensorSessionContext?, lastConnection: Date?) -> SensorPresentationProfile? {
        guard let context else { return nil }
        var p = SensorPresentationProfile(
            family: context.family,
            productType: context.productType,
            securityVersion: context.securityVersion
        )
        p.serialRedacted = context.serialRedacted
        p.warmupMinutes = context.warmupMinutes
        p.wearMinutes = context.wearMinutes
        p.receiverIDPartial = context.receiverIDPartial
        p.lastConnection = lastConnection
        if let epoch = context.activationTimeEpochS {
            let activatedAt = Date(timeIntervalSince1970: TimeInterval(epoch))
            p.warmupEndsAt = activatedAt.addingTimeInterval(Double(context.warmupMinutes) * 60)
            p.sessionEndsAt = activatedAt.addingTimeInterval(Double(context.wearMinutes) * 60)
        }
        return p
    }

    private static func note(_ reason: IncompatibilityReason) -> String {
        switch reason {
        case .unsupportedVariant(let productType, let securityVersion):
            String(localized: "sensor.note.variant", defaultValue: "Variante no compatible (productType \(Int(productType)), securityVersion \(Int(securityVersion))). No se intenta activar.")
        case .sensorEnded(let stateByte):
            String(localized: "sensor.note.ended", defaultValue: "El sensor informa que terminó (state \(Int(stateByte))).")
        }
    }
}
