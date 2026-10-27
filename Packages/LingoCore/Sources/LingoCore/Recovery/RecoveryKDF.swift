import CommonCrypto
import Foundation

/// PBKDF2-HMAC-SHA256 con CommonCrypto (`CCKeyDerivationPBKDF`), según `RECUPERACION_V1.md` §3.1.
public enum RecoveryKDF {
    public static let defaultIterations: UInt32 = 600_000
    public static let keyLength = 32
    public static let saltLength = 16

    /// Deriva `keyLength` bytes a partir de la frase ya normalizada (`RecoveryPassphrase.bytes`).
    public static func deriveKey(passphrase: String, salt: Data, iterations: UInt32 = defaultIterations) throws -> Data {
        guard salt.count == saltLength else { throw RecoveryCryptoError.invalidEnvelope("sal de \(salt.count) B; se esperaban \(saltLength)") }
        guard iterations >= 1 else { throw RecoveryCryptoError.invalidEnvelope("iteraciones inválidas") }
        let password = RecoveryPassphrase.bytes(passphrase)
        var derived = Data(count: keyLength)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedPtr in
            password.withUnsafeBytes { passPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.bindMemory(to: CChar.self).baseAddress, password.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress, keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw RecoveryCryptoError.backendFailure(Int(status)) }
        return derived
    }
}
