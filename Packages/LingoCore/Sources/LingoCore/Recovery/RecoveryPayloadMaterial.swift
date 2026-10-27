import Foundation

extension RecoveryPayload.AppIdentity {
    /// Material de identidad (`include_material == true`). `description` no muestra nada.
    public struct Material: Sendable, Hashable, Codable, CustomStringConvertible {
        public var privateKeyHex: String
        public var certificateHex: String
        public var patchSigningPublicKeyHex: String
        public var extra: [String: RecoveryJSONValue]

        public init(privateKeyHex: String, certificateHex: String, patchSigningPublicKeyHex: String,
                    extra: [String: RecoveryJSONValue] = [:]) {
            self.privateKeyHex = privateKeyHex
            self.certificateHex = certificateHex
            self.patchSigningPublicKeyHex = patchSigningPublicKeyHex
            self.extra = extra
        }

        public var description: String { "Material(‹redactado›)" }

        static let keys: Set<String> = ["private_key_hex", "certificate_hex", "patch_signing_public_key_hex"]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
            privateKeyHex = try c.required(String.self, "private_key_hex")
            certificateHex = try c.required(String.self, "certificate_hex")
            patchSigningPublicKeyHex = try c.required(String.self, "patch_signing_public_key_hex")
            extra = try c.extras(excluding: Self.keys)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: RecoveryCodingKey.self)
            try c.put(privateKeyHex, "private_key_hex")
            try c.put(certificateHex, "certificate_hex")
            try c.put(patchSigningPublicKeyHex, "patch_signing_public_key_hex")
            try c.putExtras(extra, excluding: Self.keys)
        }
    }
}
