import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Acciones reales sobre `SensorSessionCoordinator`. Las guardas de protocolo viven en el
/// coordinador y en `ActivationTicketFactory`; aquí solo se encadenan y se comprueban
/// credenciales antes de preparar nada.
@MainActor
final class LiveSensorActions: SensorActions {
    private let coordinator: SensorSessionCoordinator
    private let credentials: any PairingCredentialsProviding
    private let pairingStore: any PairingStatePersisting
    private let clock: @Sendable () -> Date
    /// Sesión `prepared` cuyo resumen se está mostrando.
    private var prepared: PreparedActivation?

    init(
        coordinator: SensorSessionCoordinator,
        credentials: any PairingCredentialsProviding,
        pairingStore: any PairingStatePersisting,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.coordinator = coordinator
        self.credentials = credentials
        self.pairingStore = pairingStore
        self.clock = clock
    }

    func readSensor() async throws {
        // `identify()` llama a `NFCService.readPatchInfo()` (solo `0xA1`) y fija
        // `identified`/`incompatible`/`readyToActivate` según familia y `stateByte`.
        try await coordinator.identify()
    }

    func credentialBlocker() async -> ActivationBlocker? {
        do {
            _ = try await credentials.identity(for: RWDKSensorFamily.lingo)
        } catch {
            return .noLingoIdentity
        }
        guard let keys = try? await credentials.signingKeys(for: RWDKSensorFamily.lingo), !keys.isEmpty else {
            return .noSigningKeys
        }
        return nil
    }

    func prepareActivation() async throws -> ActivationSummary {
        if let blocker = await credentialBlocker() {
            throw SensorActionFailure(
                title: String(localized: "activation.blocked.title", defaultValue: "No se puede activar"),
                message: blocker.explanation
            )
        }
        guard case .readyToActivate(let profile) = await coordinator.state else {
            throw SensorSessionCoordinatorError.invalidState(await coordinator.state.logLabel)
        }
        // Reutilizar sesión y Receiver ID (`prepared` o `failed` antes del 0xA0) lo decide el
        // coordinador (D-22); aquí solo se evita volver a preguntarle con la hoja aún abierta.
        let ready: PreparedActivation
        if let prepared, prepared.profile == profile {
            ready = prepared
        } else {
            ready = try await coordinator.prepareActivation(for: profile)
        }
        prepared = ready
        return ActivationSummary(
            family: CoreSensorFamily(rawValue: profile.family.rawValue) ?? .unknown,
            productType: Int(profile.productType),
            securityVersion: Int(profile.securityVersion),
            serialRedacted: profile.redactedSerial,
            warmupMinutes: profile.warmupMinutes,
            wearMinutes: profile.wearMinutes,
            receiverID: ready.receiverID,
            preparedAt: clock()
        )
    }

    func activate(_ confirmation: ActivationConfirmation) async throws {
        guard let prepared else {
            throw SensorSessionCoordinatorError.invalidState("sin activación preparada")
        }
        self.prepared = nil
        let ticket = try await ActivationTicketFactory.issue(
            profile: prepared.profile,
            sessionID: prepared.sessionID,
            confirmationID: confirmation.confirmationID,
            store: pairingStore
        )
        try await coordinator.activate(ticket: ticket)
    }
}
