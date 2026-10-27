import Foundation

/// Errores tipados de importación y consulta de credenciales. La descripción
/// nombra solo el campo o la causa; nunca incluye bytes de clave, certificado
/// ni JSON.
enum CredentialImportError: Error, Equatable, CustomStringConvertible {
    case unreadableSource
    case invalidJSON
    case unsupportedFormat
    case invalidHex(field: String)
    case invalidPrivateKey
    case invalidCertificate
    case keyCertificateMismatch
    case invalidPatchSigningPublicKey
    case invalidProductTypes
    case invalidSecurityVersions
    case noIdentities
    case keychain(status: Int32)
    case noIdentity(family: String)
    case noSigningKeys(family: String)

    var description: String {
        switch self {
        case .unreadableSource: "campo: archivo de origen ilegible"
        case .invalidJSON: "campo: JSON de identidad"
        case .unsupportedFormat: "campo: format/curve"
        case .invalidHex(let field): "campo: \(field) (hex inválido)"
        case .invalidPrivateKey: "campo: privateKeyHex"
        case .invalidCertificate: "campo: certificateHex"
        case .keyCertificateMismatch: "campo: privateKeyHex/certificateHex no coinciden"
        case .invalidPatchSigningPublicKey: "campo: patchSigningPublicKeyHex"
        case .invalidProductTypes: "campo: productTypes"
        case .invalidSecurityVersions: "campo: securityVersions"
        case .noIdentities: "campo: identities (vacío)"
        case .keychain(let status): "Keychain: OSStatus \(status)"
        case .noIdentity(let family): "sin identidad para la familia \(family)"
        case .noSigningKeys(let family): "sin claves de firma para la familia \(family)"
        }
    }
}
