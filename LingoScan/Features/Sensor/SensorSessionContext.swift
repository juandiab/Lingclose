import Foundation
import LingoCore

/// Datos no secretos de la sesión guardada (`PairingState`) que completan el estado del
/// coordinador para la UI. El Receiver ID solo se usa para mostrarlo recortado.
struct SensorSessionContext: Sendable, Equatable {
    var family: CoreSensorFamily
    var productType: Int
    var securityVersion: Int
    var serialRedacted: String
    var warmupMinutes: Int
    var wearMinutes: Int
    var activationTimeEpochS: Int64?
    var activationState: ActivationState
    var receiverID: UInt32?

    init(state: PairingState, receiverID: UInt32?) {
        family = CoreSensorFamily(rawValue: state.family.rawValue) ?? .unknown
        productType = Int(state.productType)
        securityVersion = Int(state.securityVersion)
        serialRedacted = state.serialRedacted
        warmupMinutes = state.warmupMinutes
        wearMinutes = state.wearMinutes
        activationTimeEpochS = state.activationTimeEpochS
        activationState = state.activation.state
        self.receiverID = receiverID
    }

    /// "••••" + últimos 4 dígitos hexadecimales.
    var receiverIDPartial: String? {
        guard let receiverID else { return nil }
        let hex = String(receiverID, radix: 16, uppercase: true)
        return "••••" + String(String(repeating: "0", count: max(0, 4 - hex.count)) + hex).suffix(4)
    }
}
