import CryptoKit
import Foundation

/// An app credential: a phone certificate plus the P-256 scalar behind its
/// public key. The host supplies these to RoundWhiteDiscKit before pairing;
/// the package never ships or fetches key material of its own.
///
/// kAuth is plain ECDH and SHA-256, and Phase 5/6 use standard AES-CCM.
public struct AppIdentity: Sendable {
    public let label: String
    public let privateKey: P256.KeyAgreement.PrivateKey
    public let certificate: PhoneCert
    /// NFC `productType` values this identity serves. `nil` = legacy identity
    /// without a declaration; it is treated as Libre 3 only.
    public let productTypes: [UInt8]?
    /// NFC `securityVersion` values this identity serves (informational for
    /// selection; the family rule already pins Lingo to version 3).
    public let securityVersions: [UInt16]?
    /// 65-byte uncompressed P-256 point (`0x04 || X || Y`) that verifies the
    /// sensor certificates paired with this identity. Validated on the curve.
    public let patchSigningPublicKey: Data?

    /// Build from a 32-byte P-256 scalar and a 162-byte phone certificate. The
    /// scalar must be the private key behind the certificate's public point.
    public init(
        label: String,
        privateKey: P256.KeyAgreement.PrivateKey,
        certificate: PhoneCert,
        productTypes: [UInt8]? = nil,
        securityVersions: [UInt16]? = nil,
        patchSigningPublicKey: Data? = nil
    ) throws {
        guard privateKey.publicKey.x963Representation == certificate.staticPub else {
            throw AppIdentityError.keyCertificateMismatch(label)
        }
        if let patchSigningPublicKey {
            try PatchSigningKeys.validate(patchSigningPublicKey, label: label)
        }
        self.label = label
        self.privateKey = privateKey
        self.certificate = certificate
        self.productTypes = productTypes
        self.securityVersions = securityVersions
        self.patchSigningPublicKey = patchSigningPublicKey
    }

    /// Whether this identity serves `family`. Identities without
    /// `productTypes` count only for `.libre3` (backward compatibility).
    public func serves(_ family: SensorFamily) -> Bool {
        guard let wanted = family.productType else { return false }
        guard let productTypes else { return family == .libre3 }
        return productTypes.contains(wanted)
    }

    /// NIST SP 800-56A concat KDF: `SHA-256(00000001 || Ze || Zs)[0..<16]`, where
    /// Ze is ephemeral × sensor ephemeral and Zs is our static × sensor static.
    public func authKey(
        phoneEphemeral: P256.KeyAgreement.PrivateKey,
        sensorEphemeral: P256.KeyAgreement.PublicKey,
        sensorStatic: P256.KeyAgreement.PublicKey
    ) throws -> Data {
        let ze = try EphemeralExchange.sharedSecret(privateKey: phoneEphemeral, peer: sensorEphemeral)
        let zs = try EphemeralExchange.sharedSecret(privateKey: privateKey, peer: sensorStatic)
        let digest = SHA256.hash(data: Data([0, 0, 0, 1]) + ze + zs)
        return Data(digest.prefix(16))
    }

    /// Standard AES for the Phase 5/6 exchange under a kAuth from `authKey`.
    public static let phase5Cipher: (Data) throws -> AESBlockEncrypt = { key in
        AESCCM.commonCryptoBlockEncrypt(key: key)
    }
}

/// The app credentials in use, supplied by the host at initialization. Pairing
/// tries them in order.
public enum AppIdentities {
    private static let lock = NSLock()
    private static var current: [AppIdentity]?

    /// Install host-supplied credentials. Replaces any previously installed set.
    public static func install(_ identities: [AppIdentity]) {
        lock.withLock { current = identities }
    }

    /// Install from host-supplied JSON: `{ "format": 1, "curve": "P-256",
    /// "identities": [ { "label", "privateKeyHex", "certificateHex",
    /// "productTypes"?, "securityVersions"?, "patchSigningPublicKeyHex"? } ] }`.
    public static func install(json: Data) throws {
        install(try parse(json: json))
    }

    public static var isInstalled: Bool {
        lock.withLock { current != nil }
    }

    public static func installed() throws -> [AppIdentity] {
        guard let identities = lock.withLock({ current }) else {
            throw AppIdentityError.notInstalled
        }
        return identities
    }

    /// First installed identity that serves `family`, or `nil`. `.unknown`
    /// never matches. Throws `notInstalled` if nothing was installed.
    public static func identity(for family: SensorFamily) throws -> AppIdentity? {
        identity(for: family, in: try installed())
    }

    /// First identity in `identities` that serves `family`, or `nil`.
    public static func identity(for family: SensorFamily, in identities: [AppIdentity]) -> AppIdentity? {
        identities.first { $0.serves(family) }
    }

    static func parse(json: Data) throws -> [AppIdentity] {
        let file = try JSONDecoder().decode(File.self, from: json)
        guard file.format == 1, file.curve == "P-256" else {
            throw AppIdentityError.unsupportedFormat(file.format, file.curve)
        }
        return try file.identities.map { entry in
            guard let scalar = Data(appIdentityHex: entry.privateKeyHex),
                  let certRaw = Data(appIdentityHex: entry.certificateHex) else {
                throw AppIdentityError.badHex(entry.label)
            }
            var signingKey: Data?
            if let keyHex = entry.patchSigningPublicKeyHex {
                guard let key = Data(appIdentityHex: keyHex) else {
                    throw AppIdentityError.badHex(entry.label)
                }
                signingKey = key
            }
            if let productTypes = entry.productTypes {
                guard !productTypes.isEmpty, productTypes.allSatisfy({ (0...255).contains($0) }) else {
                    throw AppIdentityError.invalidProductTypes(entry.label)
                }
            }
            if let versions = entry.securityVersions {
                guard !versions.isEmpty, versions.allSatisfy({ (0...0xFFFF).contains($0) }) else {
                    throw AppIdentityError.invalidSecurityVersions(entry.label)
                }
            }
            return try AppIdentity(
                label: entry.label,
                privateKey: P256.KeyAgreement.PrivateKey(rawRepresentation: scalar),
                certificate: PhoneCert(raw: certRaw),
                productTypes: entry.productTypes.map { $0.map(UInt8.init) },
                securityVersions: entry.securityVersions.map { $0.map(UInt16.init) },
                patchSigningPublicKey: signingKey
            )
        }
    }

    private struct File: Decodable {
        let format: Int
        let curve: String
        let identities: [Entry]
    }

    /// All fields after `certificateHex` are optional, so format-1 files
    /// written before T-02 still load unchanged.
    private struct Entry: Decodable {
        let label: String
        let privateKeyHex: String
        let certificateHex: String
        let productTypes: [Int]?
        let securityVersions: [Int]?
        let patchSigningPublicKeyHex: String?
    }
}

/// Trusted patch-signing keys per sensor family. Lingo keys are never bundled:
/// they arrive at runtime inside host-supplied identities.
public enum PatchSigningKeys {
    /// Keys that may verify a sensor certificate of `family`.
    ///
    /// - `.libre3`: `Libre3PatchSigningKey.known` plus keys declared by Libre 3
    ///   identities (deduplicated, bundled keys first).
    /// - `.lingo`: ONLY keys declared by Lingo identities. Libre 3 keys are
    ///   never mixed in, so a Lingo pairing cannot succeed against them.
    /// - `.unknown`: empty. `PairingFlow` rejects an empty list.
    public static func keys(for family: SensorFamily, identities: [AppIdentity]) -> [Data] {
        let declared = identities
            .filter { $0.serves(family) }
            .compactMap(\.patchSigningPublicKey)
        var result: [Data]
        switch family {
        case .libre3:
            result = Libre3PatchSigningKey.known
        case .lingo:
            result = []
        case .unknown:
            return []
        }
        for key in declared where !result.contains(key) {
            result.append(key)
        }
        return result
    }

    /// Throws unless `key` is a 65-byte `0x04`-prefixed point on P-256.
    static func validate(_ key: Data, label: String) throws {
        guard key.count == 65, key.first == 0x04 else {
            throw AppIdentityError.invalidPatchSigningPublicKey(label)
        }
        do {
            _ = try P256.Signing.PublicKey(x963Representation: key)
        } catch {
            throw AppIdentityError.invalidPatchSigningPublicKey(label)
        }
    }
}

public enum AppIdentityError: Error, Equatable {
    case notInstalled
    case unsupportedFormat(Int, String)
    case badHex(String)
    case keyCertificateMismatch(String)
    case invalidPatchSigningPublicKey(String)
    case invalidProductTypes(String)
    case invalidSecurityVersions(String)
}

private extension Data {
    init?(appIdentityHex hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
