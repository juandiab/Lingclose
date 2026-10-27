import Foundation
import LingoCore

/// Resumen de lo que se enviará al activar. Lo muestra `ActivationConfirmationView` antes de confirmar.
struct ActivationSummary: Sendable, Hashable, Identifiable {
    let id = UUID()
    let family: SensorFamily
    let productType: Int
    let securityVersion: Int
    /// Receiver ID parcial; nunca completo.
    let receiverIDPartial: String
    /// Hora en que se preparó el resumen.
    let preparedAt: Date
}
