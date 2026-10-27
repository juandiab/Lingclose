import Foundation
import LingoCore

/// `HealthSink` en memoria (sin HealthKit). Reemplaza por `sync_identifier` si la versión no es menor, como Health.
actor InMemoryHealthSink: HealthSink {
    var status: HealthAuthorizationStatus = .authorized
    /// Sujetos (por `sync_identifier`) cuya escritura falla mientras esté en el conjunto.
    var failingIdentifiers: Set<String> = []
    var writeError: HealthSinkError?
    /// Tipos sin permiso de escritura (como `HealthKitSink` con grasa denegada): sus muestras salen `failed`.
    var deniedKinds: Set<HealthSubjectKind> = []
    var queryError: HealthSinkError?
    /// Muestras ya presentes en Health aunque el ledger no lo sepa (escritura perdida tras `unknown`).
    private(set) var samples: [String: HealthSampleSpec] = [:]
    private(set) var writeCalls = 0
    private(set) var attemptedIdentifiers: [String] = []
    private(set) var workoutResult: [HealthWorkoutSummary] = []

    func setStatus(_ value: HealthAuthorizationStatus) { status = value }
    func setFailing(_ ids: Set<String>) { failingIdentifiers = ids }
    func setDenied(_ kinds: Set<HealthSubjectKind>) { deniedKinds = kinds }
    func setWriteError(_ error: HealthSinkError?) { writeError = error }
    func setQueryError(_ error: HealthSinkError?) { queryError = error }
    func preload(_ spec: HealthSampleSpec) { samples[spec.syncIdentifier] = spec }
    func setWorkouts(_ value: [HealthWorkoutSummary]) { workoutResult = value }

    func authorizationStatus() async -> HealthAuthorizationStatus { status }
    func requestAuthorization() async throws {
        if status == .notDetermined { status = .authorized }
    }

    func write(samples specs: [HealthSampleSpec]) async throws -> [HealthWriteResult] {
        writeCalls += 1
        if let writeError { throw writeError }
        return specs.map { spec in
            attemptedIdentifiers.append(spec.syncIdentifier)
            if deniedKinds.contains(spec.kind) {
                return HealthWriteResult(syncIdentifier: spec.syncIdentifier, outcome: .failed, detail: "sin permiso de \(spec.kind.rawValue)")
            }
            if failingIdentifiers.contains(spec.syncIdentifier) {
                return HealthWriteResult(syncIdentifier: spec.syncIdentifier, outcome: .failed, detail: "simulado")
            }
            if let existing = samples[spec.syncIdentifier], existing.syncVersion > spec.syncVersion {
                return HealthWriteResult(syncIdentifier: spec.syncIdentifier, outcome: .written)
            }
            samples[spec.syncIdentifier] = spec
            return HealthWriteResult(syncIdentifier: spec.syncIdentifier, outcome: .written)
        }
    }

    func query(syncIdentifiers: Set<String>) async throws -> Set<String> {
        if let queryError { throw queryError }
        return syncIdentifiers.intersection(samples.keys)
    }

    func workouts(in range: ClosedRange<UTCInstant>) async throws -> [HealthWorkoutSummary] {
        workoutResult.filter { $0.end >= range.lowerBound && $0.start <= range.upperBound }
    }
}

/// Reloj manual para el exportador.
final class HealthTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { value = start }
    var now: Date { lock.withLock { value } }
    func advance(seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

/// Política mutable compartida con el exportador.
final class HealthPolicyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: HealthExportPolicy
    init(_ value: HealthExportPolicy = .active) { self.value = value }
    var policy: HealthExportPolicy {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

enum HealthFixtures {
    static let activation: Int64 = 1_800_000_000 - 8 * 3_600
    static let warmup = 60
    static let tz = "America/Bogota"

    static func makeStore() throws -> SQLiteStore {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "t09-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        return try SQLiteStore(path: path)
    }

    static func session(id: String = UUID().uuidString.lowercased(), synthetic: Bool = false) -> SensorSessionRecord {
        SensorSessionRecord(
            sessionID: id, sensorFamily: .lingo, productType: 9, securityVersion: 3,
            sensorSerialHash: String(repeating: "cd", count: 32), synthetic: synthetic, sensorSerialRedacted: "TST…",
            warmupMinutes: warmup, wearMinutes: 20_160, activationTimeEpochS: activation,
            activationTimeSource: .command, activatedByAppID: "com.otalvaro.lingoscan", activationSource: .thisApp,
            activationState: .authenticated, receiverIDPresent: true
        )
    }

    static func reading(_ session: SensorSessionRecord, lifeCount: Int, value: Int = 110, trend: Int = 3,
                        qualityFlag: Bool = false) -> GlucoseReading {
        let raw = RawReading(capped: value, uncapped: value, trend: trend, qualityFlag: qualityFlag, channel: 1)
        return GlucoseReading.make(session: session, lifeCount: lifeCount, raw: raw, origin: .live,
                                   receivedAt: UTCInstant(epochSeconds: activation + 60 * Int64(lifeCount) + 1), tzAtCapture: tz)
    }

    static func meal(carbs: Double? = 45, text: String? = "arepa con huevo", kind: DiaryEventKind = .meal,
                     synthetic: Bool = false, at: Int64 = 1_800_000_000 - 3_600) -> DiaryEvent {
        DiaryEvent(eventID: UUID().uuidString.lowercased(), kind: kind, at: UTCInstant(epochSeconds: at), tz: tz,
                   carbsG: carbs, text: text, createdAt: UTCInstant(epochSeconds: at), updatedAt: UTCInstant(epochSeconds: at),
                   editID: UUID().uuidString.lowercased(), editedByAppID: "com.otalvaro.lingoscan", synthetic: synthetic)
    }
}
