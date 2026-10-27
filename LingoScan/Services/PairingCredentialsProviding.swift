import Foundation
import RoundWhiteDiscKit

/// Identidad de app y claves de firma por familia (`CredentialStore` en la app).
protocol PairingCredentialsProviding: Sendable {
    func identity(for family: RWDKSensorFamily) async throws -> AppIdentity
    /// Nunca vacía: lanza si no hay claves.
    func signingKeys(for family: RWDKSensorFamily) async throws -> [Data]
}
