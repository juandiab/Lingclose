import Foundation

extension RecoveryPayload {
    /// Una sesión de `sessions[]` (§3.2). `attempt_id`, `sequence` y `updated_at_utc` son C7.
    public struct Session: Sendable, Hashable, Codable, CustomStringConvertible {
        public var sessionID: String
        public var sensorSerial: String?
        public var sensorSerialHash: String
        public var productType: Int?
        public var securityVersion: Int?
        public var firmwareHex: String?
        public var patchInfoHex: String?
        public var attemptID: String
        public var sequence: Int
        public var updatedAtUTC: String
        public var activation: Activation
        public var ble: BLE
        public var auth: Auth
        public var sensorCertificateHex: String?
        public var extra: [String: RecoveryJSONValue]

        public init(
            sessionID: String,
            sensorSerial: String?,
            sensorSerialHash: String,
            productType: Int?,
            securityVersion: Int?,
            firmwareHex: String?,
            patchInfoHex: String?,
            attemptID: String,
            sequence: Int,
            updatedAtUTC: String,
            activation: Activation,
            ble: BLE,
            auth: Auth,
            sensorCertificateHex: String? = nil,
            extra: [String: RecoveryJSONValue] = [:]
        ) {
            self.sessionID = sessionID
            self.sensorSerial = sensorSerial
            self.sensorSerialHash = sensorSerialHash
            self.productType = productType
            self.securityVersion = securityVersion
            self.firmwareHex = firmwareHex
            self.patchInfoHex = patchInfoHex
            self.attemptID = attemptID
            self.sequence = sequence
            self.updatedAtUTC = updatedAtUTC
            self.activation = activation
            self.ble = ble
            self.auth = auth
            self.sensorCertificateHex = sensorCertificateHex
            self.extra = extra
        }

        /// Sin serial, PIN, kAuth, MAC ni respuesta NFC.
        public var description: String {
            "Session(\(sessionID), attempt \(attemptID), seq \(sequence), \(activation.state.rawValue))"
        }

        static let keys: Set<String> = [
            "session_id", "sensor_serial", "sensor_serial_hash", "product_type", "security_version",
            "firmware_hex", "patch_info_hex", "attempt_id", "sequence", "updated_at_utc",
            "activation", "ble", "auth", "sensor_certificate_hex",
        ]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
            sessionID = try c.required(String.self, "session_id")
            sensorSerial = try c.nullable(String.self, "sensor_serial")
            sensorSerialHash = try c.required(String.self, "sensor_serial_hash")
            productType = try c.nullable(Int.self, "product_type")
            securityVersion = try c.nullable(Int.self, "security_version")
            firmwareHex = try c.nullable(String.self, "firmware_hex")
            patchInfoHex = try c.nullable(String.self, "patch_info_hex")
            attemptID = try c.required(String.self, "attempt_id")
            sequence = try c.required(Int.self, "sequence")
            updatedAtUTC = try c.required(String.self, "updated_at_utc")
            activation = try c.required(Activation.self, "activation")
            ble = try c.required(BLE.self, "ble")
            auth = try c.required(Auth.self, "auth")
            sensorCertificateHex = try c.nullable(String.self, "sensor_certificate_hex")
            extra = try c.extras(excluding: Self.keys)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: RecoveryCodingKey.self)
            try c.put(sessionID, "session_id")
            try c.putNullable(sensorSerial, "sensor_serial")
            try c.put(sensorSerialHash, "sensor_serial_hash")
            try c.putNullable(productType, "product_type")
            try c.putNullable(securityVersion, "security_version")
            try c.putNullable(firmwareHex, "firmware_hex")
            try c.putNullable(patchInfoHex, "patch_info_hex")
            try c.put(attemptID, "attempt_id")
            try c.put(sequence, "sequence")
            try c.put(updatedAtUTC, "updated_at_utc")
            try c.put(activation, "activation")
            try c.put(ble, "ble")
            try c.put(auth, "auth")
            try c.putNullable(sensorCertificateHex, "sensor_certificate_hex")
            try c.putExtras(extra, excluding: Self.keys)
        }
    }
}
