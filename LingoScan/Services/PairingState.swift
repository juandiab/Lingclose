import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Estado no secreto de una sesión de pairing (`pairing-state-<session_id>.json`,
/// `ARQUITECTURA.md` §6). Los secretos van en `PairingSecrets`.
struct PairingState: Sendable, Equatable, Codable {
    var activation: ActivationRecord
    var family: RWDKSensorFamily
    var productType: UInt8
    var securityVersion: UInt16
    var warmupMinutes: Int
    var wearMinutes: Int
    var firmwareHex: String
    var stateByte: UInt8
    var serialRedacted: String
    var identityLabel: String?
    /// `CBPeripheral.identifier`: pista local, no portable.
    var peripheralUUID: UUID?
    var lastLifeCount: Int?
    /// Último lifeCount válido de historial (ancla del backfill `01 02`).
    var lastHistoricLifeCount: Int?
    var activationTimeEpochS: Int64?
    /// Último fallo de autenticación. Mientras exista no se empareja automáticamente.
    var authFailurePhase: PairingPhase?
    var authFailureSummary: String?
    /// Rol de recolectora transferido.
    var collectorPaused: Bool
    /// El sensor respondió `B1` al `0xA0` de esta sesión: su Receiver ID no se reutiliza (D-22).
    /// Opcional para leer los JSON anteriores.
    var receiverIDRejected: Bool?

    var sessionID: String { activation.sessionID }

    init(activation: ActivationRecord, profile: SensorProfile) {
        self.activation = activation
        self.family = profile.family
        self.productType = profile.productType
        self.securityVersion = profile.securityVersion
        self.warmupMinutes = profile.warmupMinutes
        self.wearMinutes = profile.wearMinutes
        self.firmwareHex = profile.firmwareHex
        self.stateByte = profile.stateByte
        self.serialRedacted = profile.redactedSerial
        self.identityLabel = nil
        self.peripheralUUID = nil
        self.lastLifeCount = nil
        self.lastHistoricLifeCount = nil
        self.activationTimeEpochS = nil
        self.authFailurePhase = nil
        self.authFailureSummary = nil
        self.collectorPaused = false
        self.receiverIDRejected = nil
    }

    /// Reconstruye el perfil con el serial guardado en Keychain.
    func profile(serial: String) -> SensorProfile {
        SensorProfile(
            family: family, productType: productType, securityVersion: securityVersion, serial: serial,
            warmupMinutes: warmupMinutes, wearMinutes: wearMinutes, firmwareHex: firmwareHex, stateByte: stateByte
        )
    }

    enum CodingKeys: String, CodingKey {
        case activation
        case family = "sensor_family"
        case productType = "product_type"
        case securityVersion = "security_version"
        case warmupMinutes = "warmup_minutes"
        case wearMinutes = "wear_minutes"
        case firmwareHex = "firmware_hex"
        case stateByte = "state_byte"
        case serialRedacted = "sensor_serial_redacted"
        case identityLabel = "identity_label"
        case peripheralUUID = "peripheral_uuid_local"
        case lastLifeCount = "last_life_count"
        case lastHistoricLifeCount = "last_historic_life_count"
        case activationTimeEpochS = "activation_time_epoch_s"
        case authFailurePhase = "auth_failure_phase"
        case authFailureSummary = "auth_failure_summary"
        case collectorPaused = "collector_paused"
        case receiverIDRejected = "receiver_id_rejected"
    }
}
