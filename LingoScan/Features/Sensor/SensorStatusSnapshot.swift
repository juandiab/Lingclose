import Foundation

/// Estado presentable del sensor más su perfil, si lo hay.
struct SensorStatusSnapshot: Sendable, Hashable {
    var state: SensorPresentationState
    var profile: SensorPresentationProfile?
    /// Detalle de `authenticationFailed` (fase, motivo, intento incompleto).
    var failure: SensorFailureDetail?
    /// Motivo de `incompatible` en texto neutro.
    var note: String?

    static let noSensor = SensorStatusSnapshot(state: .noSensor, profile: nil)
}
