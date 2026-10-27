/// Sesión de sensor tal como la define el contrato §5.1, más `activation_state` (local).
///
/// Nunca contiene secretos (serial completo, Receiver ID, PIN, kAuth, MAC, certificados; contrato §1.7):
/// esos viven en Keychain y en el archivo de recuperación cifrado.
public struct SensorSessionRecord: Sendable, Hashable, Codable {
    public var sessionID: String
    public var sensorFamily: SensorFamily
    public var productType: Int
    public var securityVersion: Int
    /// SHA-256 hex de `"lingoscan-v1:" + serial` (seudonimización, contrato §5.1).
    public var sensorSerialHash: String
    public var aliases: [SessionAlias]
    /// `true` para fixtures y previsualizaciones. Nunca pasa a `false` (contrato §5.1, C6).
    public var synthetic: Bool
    public var sensorSerialRedacted: String?
    public var firmwareHex: String?
    public var warmupMinutes: Int
    public var wearMinutes: Int
    public var activationTimeEpochS: Int64
    public var activationTimeSource: ActivationTimeSource
    public var activatedByAppID: String
    public var activationSource: ActivationSource
    public var activationState: ActivationState
    public var receiverIDPresent: Bool
    public var endedAt: UTCInstant?
    public var endReason: SessionEndReason?
    public var lastLifeCount: Int?
    public var revision: Int
    public var importedFrom: ImportedFrom?

    /// `activated_at_utc`: siempre derivado de `activation_time_epoch_s`.
    public var activatedAt: UTCInstant { UTCInstant(epochSeconds: activationTimeEpochS) }

    public init(
        sessionID: String,
        sensorFamily: SensorFamily,
        productType: Int,
        securityVersion: Int,
        sensorSerialHash: String,
        aliases: [SessionAlias] = [],
        synthetic: Bool,
        sensorSerialRedacted: String? = nil,
        firmwareHex: String? = nil,
        warmupMinutes: Int,
        wearMinutes: Int,
        activationTimeEpochS: Int64,
        activationTimeSource: ActivationTimeSource,
        activatedByAppID: String,
        activationSource: ActivationSource,
        activationState: ActivationState,
        receiverIDPresent: Bool,
        endedAt: UTCInstant? = nil,
        endReason: SessionEndReason? = nil,
        lastLifeCount: Int? = nil,
        revision: Int = 1,
        importedFrom: ImportedFrom? = nil
    ) {
        self.sessionID = sessionID
        self.sensorFamily = sensorFamily
        self.productType = productType
        self.securityVersion = securityVersion
        self.sensorSerialHash = sensorSerialHash
        self.aliases = aliases
        self.synthetic = synthetic
        self.sensorSerialRedacted = sensorSerialRedacted
        self.firmwareHex = firmwareHex
        self.warmupMinutes = warmupMinutes
        self.wearMinutes = wearMinutes
        self.activationTimeEpochS = activationTimeEpochS
        self.activationTimeSource = activationTimeSource
        self.activatedByAppID = activatedByAppID
        self.activationSource = activationSource
        self.activationState = activationState
        self.receiverIDPresent = receiverIDPresent
        self.endedAt = endedAt
        self.endReason = endReason
        self.lastLifeCount = lastLifeCount
        self.revision = revision
        self.importedFrom = importedFrom
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sensorFamily = "sensor_family"
        case productType = "product_type"
        case securityVersion = "security_version"
        case sensorSerialHash = "sensor_serial_hash"
        case aliases
        case synthetic
        case sensorSerialRedacted = "sensor_serial_redacted"
        case firmwareHex = "firmware_hex"
        case warmupMinutes = "warmup_minutes"
        case wearMinutes = "wear_minutes"
        case activationTimeEpochS = "activation_time_epoch_s"
        case activationTimeSource = "activation_time_source"
        case activatedAt = "activated_at_utc"
        case activatedByAppID = "activated_by_app_id"
        case activationSource = "activation_source"
        case activationState = "activation_state"
        case receiverIDPresent = "receiver_id_present"
        case endedAt = "ended_at_utc"
        case endReason = "end_reason"
        case lastLifeCount = "last_life_count"
        case revision
        case importedFrom = "imported_from"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        sensorFamily = try c.decode(SensorFamily.self, forKey: .sensorFamily)
        productType = try c.decode(Int.self, forKey: .productType)
        securityVersion = try c.decode(Int.self, forKey: .securityVersion)
        sensorSerialHash = try c.decode(String.self, forKey: .sensorSerialHash)
        aliases = try c.decode([SessionAlias].self, forKey: .aliases)
        synthetic = try c.decode(Bool.self, forKey: .synthetic)
        sensorSerialRedacted = try c.decodeIfPresent(String.self, forKey: .sensorSerialRedacted)
        firmwareHex = try c.decodeIfPresent(String.self, forKey: .firmwareHex)
        warmupMinutes = try c.decode(Int.self, forKey: .warmupMinutes)
        wearMinutes = try c.decode(Int.self, forKey: .wearMinutes)
        activationTimeEpochS = try c.decode(Int64.self, forKey: .activationTimeEpochS)
        activationTimeSource = try c.decode(ActivationTimeSource.self, forKey: .activationTimeSource)
        activatedByAppID = try c.decode(String.self, forKey: .activatedByAppID)
        activationSource = try c.decode(ActivationSource.self, forKey: .activationSource)
        // Clave local de LingoScan: un paquete ajeno puede no traerla.
        activationState = try c.decodeIfPresent(ActivationState.self, forKey: .activationState) ?? .authenticated
        receiverIDPresent = try c.decode(Bool.self, forKey: .receiverIDPresent)
        endedAt = try c.decodeIfPresent(UTCInstant.self, forKey: .endedAt)
        endReason = try c.decodeIfPresent(SessionEndReason.self, forKey: .endReason)
        lastLifeCount = try c.decodeIfPresent(Int.self, forKey: .lastLifeCount)
        revision = try c.decode(Int.self, forKey: .revision)
        importedFrom = try c.decodeIfPresent(ImportedFrom.self, forKey: .importedFrom)
    }

    /// Escribe todas las claves obligatorias, con `null` explícito donde no hay valor (contrato §9).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(sensorFamily, forKey: .sensorFamily)
        try c.encode(productType, forKey: .productType)
        try c.encode(securityVersion, forKey: .securityVersion)
        try c.encode(sensorSerialHash, forKey: .sensorSerialHash)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(synthetic, forKey: .synthetic)
        try c.encodeIfPresent(sensorSerialRedacted, forKey: .sensorSerialRedacted)
        try c.encode(firmwareHex, forKey: .firmwareHex)
        try c.encode(warmupMinutes, forKey: .warmupMinutes)
        try c.encode(wearMinutes, forKey: .wearMinutes)
        try c.encode(activationTimeEpochS, forKey: .activationTimeEpochS)
        try c.encode(activationTimeSource, forKey: .activationTimeSource)
        try c.encode(activatedAt, forKey: .activatedAt)
        try c.encode(activatedByAppID, forKey: .activatedByAppID)
        try c.encode(activationSource, forKey: .activationSource)
        try c.encode(activationState, forKey: .activationState)
        try c.encode(receiverIDPresent, forKey: .receiverIDPresent)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(endReason, forKey: .endReason)
        try c.encode(lastLifeCount, forKey: .lastLifeCount)
        try c.encode(revision, forKey: .revision)
        try c.encode(importedFrom, forKey: .importedFrom)
    }
}
