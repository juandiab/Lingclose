/// Cómo se autentica la próxima conexión.
enum SessionMode: Sendable, Equatable {
    /// Primera vez tras la activación NFC: handshake completo. Un fallo es terminal.
    case firstPair
    /// Sensor ya autenticado: handshake corto con kAuth y PIN.
    case reconnect
    /// El handshake corto fue rechazado con el enlace vivo: completo en una conexión nueva.
    case fullFallback
}
