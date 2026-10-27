import LingoCore

enum ActivationTransitionError: Error, Equatable {
    case notAllowed(from: ActivationState, to: ActivationState)
    case unknownSession
}
