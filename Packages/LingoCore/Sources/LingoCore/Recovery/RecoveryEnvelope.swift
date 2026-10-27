import Foundation

/// Envoltura en claro del archivo de recuperación (`RECUPERACION_V1.md` §3.1), claves en `snake_case`.
public struct RecoveryEnvelope: Codable, Sendable, Equatable {
    public static let formatName = "lingoscan-recovery"
    public static let formatVersion = 1
    public static let kdfName = "PBKDF2-HMAC-SHA256"
    public static let cipherName = "ChaCha20-Poly1305"

    public struct Producer: Codable, Sendable, Equatable {
        public var appID: String
        public var producerTag: String
        public var appVersion: String
        public init(appID: String, producerTag: String, appVersion: String) {
            self.appID = appID; self.producerTag = producerTag; self.appVersion = appVersion
        }
        enum CodingKeys: String, CodingKey { case appID = "app_id", producerTag = "producer_tag", appVersion = "app_version" }
    }

    public struct KDF: Codable, Sendable, Equatable {
        public var name: String
        public var iterations: UInt32
        public var saltB64: String
        public var keyLength: Int
        enum CodingKeys: String, CodingKey { case name, iterations, saltB64 = "salt_b64", keyLength = "key_length" }
    }

    public struct Cipher: Codable, Sendable, Equatable {
        public var name: String
        public var nonceB64: String
        enum CodingKeys: String, CodingKey { case name, nonceB64 = "nonce_b64" }
    }

    public var format: String
    public var formatVersion: Int
    public var archiveID: String
    public var createdAtUTC: String
    public var producer: Producer
    public var kdf: KDF
    public var cipher: Cipher
    public var aad: String
    public var ciphertextB64: String
    public var tagB64: String

    enum CodingKeys: String, CodingKey {
        case format, formatVersion = "format_version", archiveID = "archive_id", createdAtUTC = "created_at_utc"
        case producer, kdf, cipher, aad, ciphertextB64 = "ciphertext_b64", tagB64 = "tag_b64"
    }

    /// Cadena AAD canónica: `lingoscan-recovery|<version>|<archive_id>|<created_at_utc>`.
    public static func aadString(formatVersion: Int = formatVersion, archiveID: String, createdAtUTC: String) -> String {
        "\(formatName)|\(formatVersion)|\(archiveID)|\(createdAtUTC)"
    }

    /// Comprueba formato, versión, algoritmos y coherencia de la AAD con `archive_id` y `created_at_utc`.
    public func validate() throws {
        guard format == Self.formatName else { throw RecoveryCryptoError.unsupportedFormat("format \(format)") }
        guard formatVersion == Self.formatVersion else { throw RecoveryCryptoError.unsupportedFormat("format_version \(formatVersion)") }
        guard kdf.name == Self.kdfName else { throw RecoveryCryptoError.unsupportedFormat("kdf \(kdf.name)") }
        guard cipher.name == Self.cipherName else { throw RecoveryCryptoError.unsupportedFormat("cipher \(cipher.name)") }
        guard kdf.keyLength == RecoveryKDF.keyLength else { throw RecoveryCryptoError.invalidEnvelope("key_length \(kdf.keyLength)") }
        guard aad == Self.aadString(formatVersion: formatVersion, archiveID: archiveID, createdAtUTC: createdAtUTC) else {
            throw RecoveryCryptoError.invalidEnvelope("aad incoherente con archive_id y created_at_utc")
        }
    }

    public static func decode(_ data: Data) throws -> RecoveryEnvelope {
        do { return try JSONDecoder().decode(RecoveryEnvelope.self, from: data) }
        catch { throw RecoveryCryptoError.invalidEnvelope("JSON: \(error.localizedDescription)") }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public enum RecoveryCryptoError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Frase incorrecta o archivo alterado. A propósito no se distingue (RECUPERACION_V1 §5 paso 2).
    case authenticationFailed
    case unsupportedFormat(String)
    case invalidEnvelope(String)
    case backendFailure(Int)

    public var description: String {
        switch self {
        case .authenticationFailed: "frase incorrecta o archivo alterado"
        case .unsupportedFormat(let what): "formato no soportado: \(what)"
        case .invalidEnvelope(let what): "envoltura inválida: \(what)"
        case .backendFailure(let code): "fallo criptográfico del sistema (\(code))"
        }
    }
}
