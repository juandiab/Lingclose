import Foundation

extension RecoveryPayload {
    /// `app_identity` (§3.2): hashes de la identidad de app y, solo con `include_material`, el material.
    public struct AppIdentity: Sendable, Hashable, Codable {
        public var label: String
        public var productTypes: [UInt8]
        public var securityVersions: [UInt16]
        public var certificateSHA256: String?
        public var patchSigningKeySHA256: String?
        public var includeMaterial: Bool
        public var material: Material?
        public var extra: [String: RecoveryJSONValue]

        public init(
            label: String,
            productTypes: [UInt8],
            securityVersions: [UInt16],
            certificateSHA256: String?,
            patchSigningKeySHA256: String?,
            includeMaterial: Bool = false,
            material: Material? = nil,
            extra: [String: RecoveryJSONValue] = [:]
        ) {
            self.label = label
            self.productTypes = productTypes
            self.securityVersions = securityVersions
            self.certificateSHA256 = certificateSHA256
            self.patchSigningKeySHA256 = patchSigningKeySHA256
            self.includeMaterial = includeMaterial
            self.material = material
            self.extra = extra
        }

        static let keys: Set<String> = [
            "label", "product_types", "security_versions", "certificate_sha256",
            "patch_signing_key_sha256", "include_material", "material",
        ]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
            label = try c.required(String.self, "label")
            productTypes = try c.required([UInt8].self, "product_types")
            securityVersions = try c.required([UInt16].self, "security_versions")
            certificateSHA256 = try c.nullable(String.self, "certificate_sha256")
            patchSigningKeySHA256 = try c.nullable(String.self, "patch_signing_key_sha256")
            includeMaterial = try c.required(Bool.self, "include_material")
            material = try c.nullable(Material.self, "material")
            extra = try c.extras(excluding: Self.keys)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: RecoveryCodingKey.self)
            try c.put(label, "label")
            try c.put(productTypes, "product_types")
            try c.put(securityVersions, "security_versions")
            try c.putNullable(certificateSHA256, "certificate_sha256")
            try c.putNullable(patchSigningKeySHA256, "patch_signing_key_sha256")
            try c.put(includeMaterial, "include_material")
            try c.putNullable(material, "material")
            try c.putExtras(extra, excluding: Self.keys)
        }
    }
}
