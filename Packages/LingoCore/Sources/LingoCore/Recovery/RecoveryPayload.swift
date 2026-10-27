import Foundation

/// Carga útil descifrada del archivo de recuperación (`RECUPERACION_V1.md` §3.2, draft.4), claves `snake_case`.
///
/// Los obligatorios no anulables se modelan como no opcionales; las hojas restantes son opcionales pero
/// su clave debe existir (se escriben como `null` explícito). Las claves desconocidas se conservan en
/// `extra` para que un round-trip no pierda nada.
public struct RecoveryPayload: Sendable, Hashable, Codable {
    public static let currentVersion = 1

    public var payloadVersion: Int
    public var exportedAtUTC: String
    public var exportedByAppID: String
    public var receiverID: UInt32
    public var receiverIDOrigin: ReceiverIDOrigin
    public var appIdentity: AppIdentity
    public var sessions: [Session]
    public var extra: [String: RecoveryJSONValue]

    public enum ReceiverIDOrigin: String, Sendable, Hashable, Codable, CaseIterable {
        case generated, manual, imported
    }

    public init(
        payloadVersion: Int = RecoveryPayload.currentVersion,
        exportedAtUTC: String,
        exportedByAppID: String,
        receiverID: UInt32,
        receiverIDOrigin: ReceiverIDOrigin,
        appIdentity: AppIdentity,
        sessions: [Session],
        extra: [String: RecoveryJSONValue] = [:]
    ) {
        self.payloadVersion = payloadVersion
        self.exportedAtUTC = exportedAtUTC
        self.exportedByAppID = exportedByAppID
        self.receiverID = receiverID
        self.receiverIDOrigin = receiverIDOrigin
        self.appIdentity = appIdentity
        self.sessions = sessions
        self.extra = extra
    }

    static let keys: Set<String> = [
        "payload_version", "exported_at_utc", "exported_by_app_id", "receiver_id",
        "receiver_id_origin", "app_identity", "sessions",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: RecoveryCodingKey.self)
        payloadVersion = try c.required(Int.self, "payload_version")
        exportedAtUTC = try c.required(String.self, "exported_at_utc")
        exportedByAppID = try c.required(String.self, "exported_by_app_id")
        receiverID = try c.required(UInt32.self, "receiver_id")
        receiverIDOrigin = try c.required(ReceiverIDOrigin.self, "receiver_id_origin")
        appIdentity = try c.required(AppIdentity.self, "app_identity")
        sessions = try c.required([Session].self, "sessions")
        extra = try c.extras(excluding: Self.keys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: RecoveryCodingKey.self)
        try c.put(payloadVersion, "payload_version")
        try c.put(exportedAtUTC, "exported_at_utc")
        try c.put(exportedByAppID, "exported_by_app_id")
        try c.put(receiverID, "receiver_id")
        try c.put(receiverIDOrigin, "receiver_id_origin")
        try c.put(appIdentity, "app_identity")
        try c.put(sessions, "sessions")
        try c.putExtras(extra, excluding: Self.keys)
    }
}
