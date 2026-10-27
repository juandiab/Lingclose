import Foundation
@testable import LingoScan

/// NFC guionado. `hangOnActivate` simula que la app muere con la escritura NFC en curso.
actor ScriptedNFC: SensorNFC {
    private let profile: SensorProfile
    private let response: ActivationResponse
    private let hangOnActivate: Bool
    private var onActivate: (@Sendable () async -> Void)?
    private(set) var readCount = 0
    private(set) var activateCount = 0

    init(profile: SensorProfile, response: ActivationResponse, hangOnActivate: Bool = false) {
        self.profile = profile
        self.response = response
        self.hangOnActivate = hangOnActivate
    }

    func setOnActivate(_ probe: @escaping @Sendable () async -> Void) { onActivate = probe }

    func readPatchInfo() -> SensorProfile {
        readCount += 1
        return profile
    }

    func activate(ticket: ActivationTicket) async throws -> ActivationResponse {
        activateCount += 1
        await onActivate?()
        if hangOnActivate { try await Task.sleep(for: .seconds(3600)) }
        return response
    }
}
