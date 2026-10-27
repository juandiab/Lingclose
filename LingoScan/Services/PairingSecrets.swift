import Foundation

/// Secretos de una sesión (Keychain, `AfterFirstUnlockThisDeviceOnly`). En las
/// escrituras, `nil` significa "no tocar". `description` no muestra nada.
struct PairingSecrets: Sendable, Equatable, CustomStringConvertible {
    var receiverID: UInt32?
    /// PIN BLE de 4 B (bytes 9-12 de la respuesta NFC; `tail4` del handshake).
    var pin: Data?
    /// kAuth de 16 B (Phase 5).
    var kAuth: Data?
    /// MAC BLE como la muestra el fork (`AA:BB:…`).
    var bleAddress: String?
    /// Respuesta NFC de activación cruda (19 B).
    var activationResponse: Data?
    /// Serial completo (9 ASCII). Decisión T-08: se guarda con los secretos, no en el JSON.
    var serial: String?

    var description: String { "PairingSecrets(‹redactado›)" }
}
