import LingoCore

/// "Conectar sensor activo" sobre `SensorSessionCoordinator` usando solo `start`, `resume` y
/// `retryPairing` (handshake corto con kAuth/PIN y, si falta kAuth o se rechaza, el completo).
/// Nunca usa `prepareActivation`/`activate`: ningún camino llega a `0xA0` ni a `0xA8`.
struct RecoveryLiveSensorConnector: RecoveryActiveSensorConnecting {
    let coordinator: SensorSessionCoordinator

    enum ConnectError: Error, Equatable, CustomStringConvertible {
        case notConnectable(ActivationState)
        case busy(String)
        case unexpectedState(String)

        var description: String {
            switch self {
            case .notConnectable(let s):
                String(localized: "recovery.connect.notConnectable", defaultValue: "Una sesión en \(s.rawValue) no se puede conectar: no hay activación desde aquí")
            case .busy(let s):
                String(localized: "recovery.connect.busy", defaultValue: "Hay una sesión en curso (\(s)); páusala antes")
            case .unexpectedState(let s):
                String(localized: "recovery.connect.unexpected", defaultValue: "Estado inesperado del sensor: \(s)")
            }
        }
    }

    func connectActiveSensor(importedState: ActivationState) async throws {
        guard importedState == .responseSaved || importedState == .authenticated else {
            throw ConnectError.notConnectable(importedState)
        }
        switch await coordinator.state {
        case .noSensor, .paused, .identified, .incompatible, .ended, .authenticationFailed:
            break
        case let other:
            throw ConnectError.busy(other.logLabel)
        }
        // Relee el estado persistido: la sesión importada es la más reciente y está en pausa.
        await coordinator.start()
        guard case .paused = await coordinator.state else {
            throw ConnectError.unexpectedState(await coordinator.state.logLabel)
        }
        await coordinator.resume()
        // `response_saved` arranca como emparejamiento sin terminar: el usuario acaba de confirmarlo.
        if case .authenticationFailed = await coordinator.state {
            try await coordinator.retryPairing()
        }
    }
}
