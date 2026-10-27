import Foundation
import Observation

/// Estado y acciones de la pantalla Sensor. No contiene lógica de protocolo ni NFC:
/// las acciones llegan por closure desde quien conecte T-08.
@MainActor
@Observable
final class SensorViewModel {
    private(set) var status: SensorStatusSnapshot
    private(set) var lastConfirmation: ActivationConfirmation?
    private(set) var isReading = false
    /// Resumen mostrado en la hoja de activación; `nil` mientras no se pide activar.
    var activationSummary: ActivationSummary?

    /// Lectura NFC de solo lectura (`0xA1`). `nil` mientras no haya adaptador.
    var readSensorAction: (@MainActor () async -> Void)?
    /// Activación con confirmación. `nil` mientras no haya adaptador.
    var activateAction: (@MainActor (ActivationConfirmation) async -> Void)?

    private let statusSource: any SensorStatusSource
    private let clock: @Sendable () -> Date

    init(statusSource: any SensorStatusSource, clock: @escaping @Sendable () -> Date = { .now }) {
        self.statusSource = statusSource
        self.clock = clock
        self.status = .noSensor
    }

    /// Carga el estado actual y sigue los cambios hasta que se cancela la tarea.
    func observe() async {
        status = await statusSource.currentStatus()
        for await snapshot in statusSource.statusUpdates() {
            status = snapshot
        }
    }

    var canReadSensor: Bool { readSensorAction != nil && !isReading }

    /// La activación solo se ofrece con sensor Lingo v3 listo, Receiver ID disponible y adaptador conectado.
    var canActivate: Bool {
        guard activateAction != nil,
              status.state == .readyToActivate,
              let profile = status.profile,
              profile.isSupportedVariant,
              profile.receiverIDPartial != nil
        else { return false }
        return true
    }

    func readSensor() async {
        guard let readSensorAction, !isReading else { return }
        isReading = true
        await readSensorAction()
        isReading = false
    }

    /// Prepara el resumen de lo que se enviaría. No activa nada.
    func beginActivation() {
        guard canActivate, let profile = status.profile, let receiver = profile.receiverIDPartial else { return }
        activationSummary = ActivationSummary(
            family: profile.family,
            productType: profile.productType,
            securityVersion: profile.securityVersion,
            receiverIDPartial: receiver,
            preparedAt: clock()
        )
    }

    /// Recibe la confirmación de la hoja y la entrega al adaptador. Aquí no se envía NFC.
    func confirmActivation(_ confirmation: ActivationConfirmation) async {
        activationSummary = nil
        lastConfirmation = confirmation
        await activateAction?(confirmation)
    }
}
