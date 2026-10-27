import CryptoKit
import Foundation
import RoundWhiteDiscKit
@testable import LingoScan

/// Identidad sintética fija, sin tocar `AppIdentities` global ni el Keychain.
struct StaticCredentials: PairingCredentialsProviding {
    let appIdentity: AppIdentity
    let keys: [Data]

    func identity(for family: RWDKSensorFamily) async throws -> AppIdentity { appIdentity }
    func signingKeys(for family: RWDKSensorFamily) async throws -> [Data] { keys }

    /// Certificado de 162 B inventado: cabecera 03 01, clave pública en 33..<98, firma de relleno.
    static func synthetic(signingPublicKey: Data, keys: [Data]? = nil) throws -> StaticCredentials {
        let privateKey = P256.KeyAgreement.PrivateKey()
        var cert = Data([0x03, 0x01])
        cert.append(Data(repeating: 0xAA, count: 31))
        cert.append(privateKey.publicKey.x963Representation)
        cert.append(Data(repeating: 0xBB, count: 64))
        let identity = try AppIdentity(
            label: "synthetic-lingo", privateKey: privateKey, certificate: try PhoneCert(raw: cert),
            productTypes: [9], securityVersions: [3], patchSigningPublicKey: signingPublicKey
        )
        return StaticCredentials(appIdentity: identity, keys: keys ?? [signingPublicKey])
    }
}
