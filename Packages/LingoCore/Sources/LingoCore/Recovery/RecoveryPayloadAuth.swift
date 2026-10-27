import Foundation

extension RecoveryPayload.Session {
    /// `auth` (§3.2). `k_auth_hex` es `null` hasta completar la Phase 6.
    public struct Auth: Sendable, Hashable, Codable {
        public var kAuthHex: String?
        public var kAuthCapturedAtUTC: String?
        public var lastSuccessfulHandshakeUTC: String?
        public var lastLifeCount: Int?
        public var extra: [String: RecoveryJSONValue]

        public init(kAuthHex: String? = nil, kAuthCapturedAtUTC: String? = nil,
                    lastSuccessfulHandshakeUTC: String? = nil, lastLifeCount: Int? = nil,
                    extra: [String: RecoveryJSONValue] = [:]) {
            self.kAuthHex = kAuthHex
            self.kAuthCapturedAtUTC = kAuthCapturedAtUTC
            self.lastSuccessfulHandshakeUTC = lastSuccessfulHandshakeUTC
            self.lastLifeCount = lastLifeCount
            self.extra = extra
        }

        static let keys: Set<String> = ["k_auth_hex", "k_auth_captured_at_utc", "last_successful_handshake_utc", "last_life_count"]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
            kAuthHex = try c.nullable(String.self, "k_auth_hex")
            kAuthCapturedAtUTC = try c.nullable(String.self, "k_auth_captured_at_utc")
            lastSuccessfulHandshakeUTC = try c.nullable(String.self, "last_successful_handshake_utc")
            lastLifeCount = try c.nullable(Int.self, "last_life_count")
            extra = try c.extras(excluding: Self.keys)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: RecoveryCodingKey.self)
            try c.putNullable(kAuthHex, "k_auth_hex")
            try c.putNullable(kAuthCapturedAtUTC, "k_auth_captured_at_utc")
            try c.putNullable(lastSuccessfulHandshakeUTC, "last_successful_handshake_utc")
            try c.putNullable(lastLifeCount, "last_life_count")
            try c.putExtras(extra, excluding: Self.keys)
        }
    }
}
