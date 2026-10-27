import Foundation

/// Un secreto pequeño guardado fuera de la base (en la app, un ítem del Keychain). Solo mueve `Data`.
/// En pruebas se sustituye por memoria para no tocar el Keychain real.
protocol SecretItemStoring: Sendable {
    /// `nil` si no existe.
    func read() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

extension KeychainItem: SecretItemStoring {}
