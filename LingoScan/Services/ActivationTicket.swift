import Foundation
import LingoCore

/// Autorización para un único `0xA0`. Solo `ActivationTicketFactory` (mismo archivo,
/// por eso la excepción a "un tipo por archivo") puede construirlo: su `init` es `fileprivate`.
struct ActivationTicket: Sendable, Equatable {
    let sessionID: String
    let attemptID: String
    let profile: SensorProfile
    let receiverID: UInt32
    /// UUID que la vista de activación genera cuando Juampa confirma por escrito.
    let confirmationID: UUID
    let issuedAt: Date

    fileprivate init(sessionID: String, attemptID: String, profile: SensorProfile, receiverID: UInt32, confirmationID: UUID, issuedAt: Date) {
        self.sessionID = sessionID
        self.attemptID = attemptID
        self.profile = profile
        self.receiverID = receiverID
        self.confirmationID = confirmationID
        self.issuedAt = issuedAt
    }
}

/// Emite tickets solo para un Lingo v3 sin activar, con la sesión en `prepared`
/// y el Receiver ID ya persistido.
enum ActivationTicketFactory {
    static func issue(
        profile: SensorProfile,
        sessionID: String,
        confirmationID: UUID,
        store: any PairingStatePersisting,
        now: Date = .now
    ) async throws -> ActivationTicket {
        guard profile.isSupportedLingo else { throw ActivationTicketError.notLingo }
        guard profile.isFresh else { throw ActivationTicketError.sensorNotFresh(stateByte: profile.stateByte) }
        guard let state = try await store.loadState(sessionID: sessionID),
              state.activation.state == .prepared else {
            throw ActivationTicketError.notPrepared
        }
        let secrets = try await store.loadSecrets(sessionID: sessionID)
        guard let receiverID = secrets.receiverID, receiverID != 0 else {
            throw ActivationTicketError.receiverIDNotPersisted
        }
        guard secrets.serial == profile.serialNumber, state.productType == profile.productType,
              state.securityVersion == profile.securityVersion else {
            throw ActivationTicketError.profileMismatch
        }
        return ActivationTicket(
            sessionID: sessionID, attemptID: state.activation.attemptID, profile: profile,
            receiverID: receiverID, confirmationID: confirmationID, issuedAt: now
        )
    }
}
