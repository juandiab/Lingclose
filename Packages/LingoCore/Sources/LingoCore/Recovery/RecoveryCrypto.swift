import CryptoKit
import Foundation

/// Sellado y apertura del archivo de recuperación (`RECUPERACION_V1.md` §3):
/// PBKDF2-HMAC-SHA256 (600 000 it., sal 16 B) + ChaCha20-Poly1305 (nonce 12 B, tag 16 B) con la AAD canónica.
/// Verificado contra `LingoScan_Shared/examples/recovery/vectors.json` (Swift y Python coinciden byte a byte).
public enum RecoveryCrypto {
    public static let nonceLength = 12
    public static let tagLength = 16

    /// Sella `plaintext` con la frase. `salt` y `nonce` solo se pasan en tests (vectores deterministas);
    /// en producción se generan aleatorios.
    public static func seal(
        plaintext: Data,
        passphrase: String,
        archiveID: String,
        createdAtUTC: String,
        producer: RecoveryEnvelope.Producer,
        iterations: UInt32 = RecoveryKDF.defaultIterations,
        salt: Data? = nil,
        nonce: Data? = nil
    ) throws -> RecoveryEnvelope {
        let salt = try salt ?? randomBytes(RecoveryKDF.saltLength)
        let nonceData = try nonce ?? randomBytes(nonceLength)
        guard nonceData.count == nonceLength else { throw RecoveryCryptoError.invalidEnvelope("nonce de \(nonceData.count) B") }
        let key = try RecoveryKDF.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let aad = RecoveryEnvelope.aadString(archiveID: archiveID, createdAtUTC: createdAtUTC)
        let sealed: ChaChaPoly.SealedBox
        do {
            sealed = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: key),
                                         nonce: ChaChaPoly.Nonce(data: nonceData), authenticating: Data(aad.utf8))
        } catch {
            throw RecoveryCryptoError.backendFailure(-1)
        }
        return RecoveryEnvelope(
            format: RecoveryEnvelope.formatName,
            formatVersion: RecoveryEnvelope.formatVersion,
            archiveID: archiveID,
            createdAtUTC: createdAtUTC,
            producer: producer,
            kdf: .init(name: RecoveryEnvelope.kdfName, iterations: iterations,
                       saltB64: salt.base64EncodedString(), keyLength: RecoveryKDF.keyLength),
            cipher: .init(name: RecoveryEnvelope.cipherName, nonceB64: nonceData.base64EncodedString()),
            aad: aad,
            ciphertextB64: sealed.ciphertext.base64EncodedString(),
            tagB64: sealed.tag.base64EncodedString()
        )
    }

    /// Abre la envoltura. Un tag inválido (frase incorrecta, AAD, nonce o texto alterados) produce
    /// siempre `authenticationFailed`, sin distinguir la causa.
    public static func open(_ envelope: RecoveryEnvelope, passphrase: String) throws -> Data {
        try envelope.validate()
        guard let salt = Data(base64Encoded: envelope.kdf.saltB64),
              let nonce = Data(base64Encoded: envelope.cipher.nonceB64),
              let ciphertext = Data(base64Encoded: envelope.ciphertextB64),
              let tag = Data(base64Encoded: envelope.tagB64) else {
            throw RecoveryCryptoError.invalidEnvelope("base64 inválido")
        }
        guard nonce.count == nonceLength, tag.count == tagLength else {
            throw RecoveryCryptoError.invalidEnvelope("tamaños de nonce o tag")
        }
        let key = try RecoveryKDF.deriveKey(passphrase: passphrase, salt: salt, iterations: envelope.kdf.iterations)
        do {
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            return try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: Data(envelope.aad.utf8))
        } catch {
            throw RecoveryCryptoError.authenticationFailed
        }
    }

    static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw RecoveryCryptoError.backendFailure(Int(status)) }
        return Data(bytes)
    }
}
