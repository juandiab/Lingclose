import Foundation
@testable import LingoScan

/// NFC guionado. `hangOnActivate` simula que la app muere con la escritura NFC en curso.
/// `failNextActivations` simula sesiones NFC que fallan antes de que el sensor acepte `0xA0`
/// (p. ej. `patchInfo` inválido tras los reintentos del fork) o con un rechazo `B1`.
actor ScriptedNFC: SensorNFC {
    private let profile: SensorProfile
    private let response: ActivationResponse
    private let hangOnActivate: Bool
    private var onActivate: (@Sendable () async -> Void)?
    private(set) var readCount = 0
    private(set) var activateCount = 0
    /// Activaciones que devolvieron la respuesta de 19 B (el sensor aceptó `0xA0`).
    private(set) var acceptedCount = 0
    private(set) var receiverIDsSeen: [UInt32] = []
    private var pendingFailures: [any Error] = []

    init(profile: SensorProfile, response: ActivationResponse, hangOnActivate: Bool = false) {
        self.profile = profile
        self.response = response
        self.hangOnActivate = hangOnActivate
    }

    func setOnActivate(_ probe: @escaping @Sendable () async -> Void) { onActivate = probe }

    func failNextActivations(_ errors: [any Error]) { pendingFailures = errors }

    func readPatchInfo() -> SensorProfile {
        readCount += 1
        return profile
    }

    func activate(ticket: ActivationTicket) async throws -> ActivationResponse {
        activateCount += 1
        receiverIDsSeen.append(ticket.receiverID)
        await onActivate?()
        if hangOnActivate { try await Task.sleep(for: .seconds(3600)) }
        if !pendingFailures.isEmpty { throw pendingFailures.removeFirst() }
        acceptedCount += 1
        return response
    }
}
