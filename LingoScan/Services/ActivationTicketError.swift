enum ActivationTicketError: Error, Equatable {
    case notLingo
    case sensorNotFresh(stateByte: UInt8)
    case notPrepared
    case receiverIDNotPersisted
    case profileMismatch
}
