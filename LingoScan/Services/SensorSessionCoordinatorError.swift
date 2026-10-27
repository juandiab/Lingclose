enum SensorSessionCoordinatorError: Error, Equatable {
    /// La operación no corresponde al estado actual (p. ej. activar sin `readyToActivate`).
    case invalidState(String)
    case ticketDoesNotMatchSession
}
