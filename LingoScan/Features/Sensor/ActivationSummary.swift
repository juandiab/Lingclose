import Foundation
import LingoCore

/// Resumen de lo que se enviará al activar. Lo muestra `ActivationConfirmationView` antes de confirmar.
/// El Receiver ID ya está persistido (sesión en `prepared`) y se muestra completo para anotarlo.
struct ActivationSummary: Sendable, Hashable, Identifiable {
    let id = UUID()
    let family: SensorFamily
    let productType: Int
    let securityVersion: Int
    /// Serial recortado; nunca completo.
    let serialRedacted: String
    let warmupMinutes: Int
    let wearMinutes: Int
    /// Receiver ID completo que se enviará en `0xA0`.
    let receiverID: UInt32
    /// Hora en que se preparó el resumen.
    let preparedAt: Date

    /// Decimal y hexadecimal, para anotarlo tal cual.
    var receiverIDText: String {
        let hex = String(receiverID, radix: 16, uppercase: true)
        return "\(receiverID) (0x\(String(repeating: "0", count: max(0, 8 - hex.count)) + hex))"
    }
}
