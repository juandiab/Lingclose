import Foundation

extension RecoveryPayload.Session {
    /// `ble` (§3.2). `peripheral_uuid_local` es solo una pista local, no portable.
    public struct BLE: Sendable, Hashable, Codable {
        public var address: String?
        public var pinHex: String?
        public var peripheralUUIDLocal: String?
        public var extra: [String: RecoveryJSONValue]

        public init(address: String? = nil, pinHex: String? = nil, peripheralUUIDLocal: String? = nil,
                    extra: [String: RecoveryJSONValue] = [:]) {
            self.address = address
            self.pinHex = pinHex
            self.peripheralUUIDLocal = peripheralUUIDLocal
            self.extra = extra
        }

        static let keys: Set<String> = ["address", "pin_hex", "peripheral_uuid_local"]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
            address = try c.nullable(String.self, "address")
            pinHex = try c.nullable(String.self, "pin_hex")
            peripheralUUIDLocal = try c.nullable(String.self, "peripheral_uuid_local")
            extra = try c.extras(excluding: Self.keys)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: RecoveryCodingKey.self)
            try c.putNullable(address, "address")
            try c.putNullable(pinHex, "pin_hex")
            try c.putNullable(peripheralUUIDLocal, "peripheral_uuid_local")
            try c.putExtras(extra, excluding: Self.keys)
        }
    }
}
