import Foundation

extension RecoveryPayload.Session {
    /// `activation` (§3.2): objeto siempre presente; solo `state` es no anulable.
    public struct Activation: Sendable, Hashable, Codable {
        public var state: ActivationState
        public var attemptedAtUTC: String?
        public var receiverIDUsed: UInt32?
        public var activationTimeEpochS: Int64?
        public var commandHex: String?
        /// 19 B crudos de la respuesta de `0xA0`.
        public var responseHex: String?
        public var error: String?
        public var extra: [String: RecoveryJSONValue]

        public init(
            state: ActivationState,
            attemptedAtUTC: String? = nil,
            receiverIDUsed: UInt32? = nil,
            activationTimeEpochS: Int64? = nil,
            commandHex: String? = nil,
            responseHex: String? = nil,
            error: String? = nil,
            extra: [String: RecoveryJSONValue] = [:]
        ) {
            self.state = state
            self.attemptedAtUTC = attemptedAtUTC
            self.receiverIDUsed = receiverIDUsed
            self.activationTimeEpochS = activationTimeEpochS
            self.commandHex = commandHex
            self.responseHex = responseHex
            self.error = error
            self.extra = extra
        }

        static let keys: Set<String> = [
            "state", "attempted_at_utc", "receiver_id_used", "activation_time_epoch_s",
            "command_hex", "response_hex", "error",
        ]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
            state = try c.required(ActivationState.self, "state")
            attemptedAtUTC = try c.nullable(String.self, "attempted_at_utc")
            receiverIDUsed = try c.nullable(UInt32.self, "receiver_id_used")
            activationTimeEpochS = try c.nullable(Int64.self, "activation_time_epoch_s")
            commandHex = try c.nullable(String.self, "command_hex")
            responseHex = try c.nullable(String.self, "response_hex")
            error = try c.nullable(String.self, "error")
            extra = try c.extras(excluding: Self.keys)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: RecoveryCodingKey.self)
            try c.put(state, "state")
            try c.putNullable(attemptedAtUTC, "attempted_at_utc")
            try c.putNullable(receiverIDUsed, "receiver_id_used")
            try c.putNullable(activationTimeEpochS, "activation_time_epoch_s")
            try c.putNullable(commandHex, "command_hex")
            try c.putNullable(responseHex, "response_hex")
            try c.putNullable(error, "error")
            try c.putExtras(extra, excluding: Self.keys)
        }
    }
}
