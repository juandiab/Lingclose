import Foundation
import Observation

/// Estado y acciones de la pantalla Sensor. No contiene lógica de protocolo ni NFC:
/// las acciones llegan por `SensorActions`.
@MainActor
@Observable
final class SensorViewModel {
    private(set) var status: SensorStatusSnapshot
    private(set) var lastConfirmation: ActivationConfirmation?
    private(set) var isReading = false
    private(set) var isPreparing = false
    /// Falta de credenciales detectada por las acciones (identidad o claves de firma).
    private(set) var credentialBlocker: ActivationBlocker?
    /// Resumen mostrado en la hoja de activación; `nil` mientras no se pide activar.
    var activationSummary: ActivationSummary?
    /// Error de la última acción, para un `alert`.
    var failure: SensorActionFailure?

    var isShowingFailure: Bool {
        get { failure != nil }
        set { if !newValue { failure = nil } }
    }

    private let statusSource: any SensorStatusSource
    private let actions: (any SensorActions)?

    init(statusSource: any SensorStatusSource, actions: (any SensorActions)? = nil) {
        self.statusSource = statusSource
        self.actions = actions
        self.status = .noSensor
    }

    /// Carga el estado actual y sigue los cambios hasta que se cancela la tarea.
    func observe() async {
        status = await statusSource.currentStatus()
        await refreshCredentialBlocker()
        for await snapshot in statusSource.statusUpdates() {
            status = snapshot
            await refreshCredentialBlocker()
        }
    }

    func refreshCredentialBlocker() async {
        credentialBlocker = await actions?.credentialBlocker()
    }

    var canReadSensor: Bool { actions != nil && !isReading }

    /// Primer motivo por el que no se puede activar; `nil` si se puede.
    var activationBlocker: ActivationBlocker? {
        guard actions != nil else { return .actionsUnavailable }
        guard status.state == .readyToActivate, let profile = status.profile else { return .sensorNotRead }
        guard profile.isSupportedVariant else { return .unsupportedVariant }
        return credentialBlocker
    }

    /// Solo Lingo v3 en `readyToActivate`, con identidad Lingo y claves de firma no vacías.
    var canActivate: Bool { activationBlocker == nil && !isPreparing }

    func readSensor() async {
        guard let actions, !isReading else { return }
        isReading = true
        defer { isReading = false }
        do {
            try await actions.readSensor()
        } catch {
            failure = SensorActionFailure(error)
        }
    }

    /// Persiste el Receiver ID (`prepared`) y abre la hoja con el resumen. No activa nada.
    func beginActivation() async {
        guard canActivate, let actions else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            activationSummary = try await actions.prepareActivation()
        } catch {
            failure = SensorActionFailure(error)
        }
    }

    /// Recibe la confirmación de la hoja y la entrega a las acciones (ticket + `0xA0`).
    func confirmActivation(_ confirmation: ActivationConfirmation) async {
        activationSummary = nil
        lastConfirmation = confirmation
        do {
            try await actions?.activate(confirmation)
        } catch {
            failure = SensorActionFailure(error)
        }
    }
}
