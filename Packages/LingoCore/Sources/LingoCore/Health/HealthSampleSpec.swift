import Foundation

/// Descripción de una muestra de Health sin tipos de HealthKit (la traduce `HealthKitSink`).
public struct HealthSampleSpec: Sendable, Hashable {
    public enum Unit: String, Sendable, Hashable {
        case milligramsPerDeciliter = "mg/dL"
        case grams = "g"
    }

    /// `glucose` → `HKQuantityType(.bloodGlucose)`; `carbs` → `.dietaryCarbohydrates`.
    public let kind: HealthSubjectKind
    public let value: Double
    /// Inicio = fin.
    public let date: UTCInstant
    /// `HKMetadataKeySyncIdentifier`.
    public let syncIdentifier: String
    /// `HKMetadataKeySyncVersion`.
    public let syncVersion: Int
    /// `HKMetadataKeyWasUserEntered`: siempre `false`; no hay forma de construir otra cosa.
    public let wasUserEntered = false
    /// `com.otalvaro.lingoscan.session`
    public let sessionID: String?
    /// `com.otalvaro.lingoscan.lifeCount`
    public let lifeCount: Int?
    /// `com.otalvaro.lingoscan.origin`
    public let origin: String?
    /// `com.otalvaro.lingoscan.trend`
    public let trend: Int?
    /// `com.otalvaro.lingoscan.note` (carbohidratos).
    public let note: String?

    public var unit: Unit { kind == .glucose ? .milligramsPerDeciliter : .grams }

    public static let metadataPrefix = "com.otalvaro.lingoscan"
    public static let sessionKey = metadataPrefix + ".session"
    public static let lifeCountKey = metadataPrefix + ".lifeCount"
    public static let originKey = metadataPrefix + ".origin"
    public static let trendKey = metadataPrefix + ".trend"
    public static let noteKey = metadataPrefix + ".note"

    public init(
        kind: HealthSubjectKind, value: Double, date: UTCInstant, syncIdentifier: String, syncVersion: Int,
        sessionID: String? = nil, lifeCount: Int? = nil, origin: String? = nil, trend: Int? = nil, note: String? = nil
    ) {
        self.kind = kind
        self.value = value
        self.date = date
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.sessionID = sessionID
        self.lifeCount = lifeCount
        self.origin = origin
        self.trend = trend
        self.note = note
    }
}

/// Resultado de escribir una muestra.
public struct HealthWriteResult: Sendable, Hashable {
    public let syncIdentifier: String
    public let outcome: HealthLedgerResult
    /// Texto no sensible del error, solo para el log.
    public let detail: String?

    public init(syncIdentifier: String, outcome: HealthLedgerResult, detail: String? = nil) {
        self.syncIdentifier = syncIdentifier
        self.outcome = outcome
        self.detail = detail
    }
}

/// Entrenamiento leído de Health (solo para superponer en la curva; nunca se escribe).
public struct HealthWorkoutSummary: Sendable, Hashable {
    public let id: String
    public let start: UTCInstant
    public let end: UTCInstant
    /// `HKWorkoutActivityType.rawValue`.
    public let activityTypeRaw: UInt
    public let sourceName: String?

    public init(id: String, start: UTCInstant, end: UTCInstant, activityTypeRaw: UInt, sourceName: String?) {
        self.id = id
        self.start = start
        self.end = end
        self.activityTypeRaw = activityTypeRaw
        self.sourceName = sourceName
    }
}

public enum HealthAuthorizationStatus: String, Sendable, Hashable {
    case authorized, denied, notDetermined, unavailable
}

public enum HealthSinkError: Error, Sendable, Hashable, CustomStringConvertible {
    /// HealthKit no existe en este dispositivo (iPad, simulador sin soporte).
    case unavailable
    case authorizationDenied
    case failed(String)

    public var description: String {
        switch self {
        case .unavailable: "HealthKit no está disponible en este dispositivo"
        case .authorizationDenied: "Salud no permite escribir (permiso denegado o sin decidir)"
        case .failed(let detail): "Salud rechazó la escritura: \(detail)"
        }
    }
}

/// Destino de las muestras. LingoCore no importa HealthKit: la app inyecta `HealthKitSink`; los tests, uno en memoria.
public protocol HealthSink: Sendable {
    func authorizationStatus() async -> HealthAuthorizationStatus
    /// Muestra la hoja de permisos (escritura de glucosa y carbohidratos; lectura de entrenamientos).
    func requestAuthorization() async throws
    /// Un resultado por muestra y en el mismo orden. Lanza `unavailable` o `authorizationDenied` si no escribió nada.
    func write(samples: [HealthSampleSpec]) async throws -> [HealthWriteResult]
    /// De los `sync_identifier` dados, los que ya existen en Health escritos por esta app.
    func query(syncIdentifiers: Set<String>) async throws -> Set<String>
    func workouts(in range: ClosedRange<UTCInstant>) async throws -> [HealthWorkoutSummary]
}
