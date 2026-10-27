import Foundation

/// Prueba de que la persona confirmó la activación. T-08 la convertirá en `ActivationTicket`.
/// Crearla no envía nada por NFC.
struct ActivationConfirmation: Sendable, Hashable, Identifiable {
    let confirmationID: UUID
    let confirmedAt: Date

    var id: UUID { confirmationID }
}
