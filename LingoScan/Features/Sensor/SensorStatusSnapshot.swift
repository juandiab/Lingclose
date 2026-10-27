import Foundation

/// Estado presentable del sensor más su perfil, si lo hay.
struct SensorStatusSnapshot: Sendable, Hashable {
    var state: SensorPresentationState
    var profile: SensorPresentationProfile?

    static let noSensor = SensorStatusSnapshot(state: .noSensor, profile: nil)
}
