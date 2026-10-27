/// Lo que la UI muestra antes de confirmar: el Receiver ID ya está guardado y la
/// sesión está en `prepared` (`RECUPERACION_V1.md` §4.1).
struct PreparedActivation: Sendable, Equatable {
    let sessionID: String
    let attemptID: String
    let receiverID: UInt32
    let profile: SensorProfile
}
