import Foundation
import LingoCore
@testable import LingoScan

/// Lecturas en memoria, perfil de Salud falso y servicio armado con Llavero y ajustes en memoria.
/// Nada real: ni clave, ni red, ni Salud, ni SQLite.
struct InMemoryRangeReadings: RangeReadingsSource {
    var readings: [GlucoseReading]

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        readings.filter { range.contains($0.measuredAt) }
    }
}

struct FailingRangeReadings: RangeReadingsSource {
    struct Boom: Error {}
    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] { throw Boom() }
}

struct FakeHealthProfileReader: HealthProfileReading {
    var profile = HealthProfile(ageYears: 41, biologicalSex: .male, weightKg: 78.5, heightCm: 176)
    var error: HealthProfileError?

    func readProfile() async throws -> HealthProfile {
        if let error { throw error }
        return profile
    }
}

enum RangeFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let tz = "America/Bogota"
    /// Activación 10 días antes de `now`, sin calentamiento para que todas las lecturas cuenten.
    static let activation: Int64 = 1_800_000_000 - 10 * 86_400

    static let session = SensorSessionRecord(
        sessionID: "range-test-session", sensorFamily: .lingo, productType: 9, securityVersion: 3,
        sensorSerialHash: String(repeating: "ab", count: 32), synthetic: false, sensorSerialRedacted: "TST…",
        warmupMinutes: 0, wearMinutes: 20_160, activationTimeEpochS: activation,
        activationTimeSource: .command, activatedByAppID: "com.otalvaro.lingoscan", activationSource: .thisApp,
        activationState: .authenticated, receiverIDPresent: true)

    /// Una lectura por minuto durante `hours` horas terminando en `now`, con valores que ciclan por `values`.
    static func readings(hours: Int, values: [Int] = [82, 95, 104, 110, 126, 141, 99, 88, 117, 133]) -> [GlucoseReading] {
        let total = hours * 60
        let lastLifeCount = 10 * 24 * 60
        return (0..<total).map { i in
            let lifeCount = lastLifeCount - total + 1 + i
            let raw = RawReading(capped: values[i % values.count], uncapped: values[i % values.count], trend: 3, qualityFlag: false, channel: 1)
            return GlucoseReading.make(session: session, lifeCount: lifeCount, raw: raw, origin: .live,
                                       receivedAt: UTCInstant(epochSeconds: activation + 60 * Int64(lifeCount) + 1), tzAtCapture: tz)
        }
    }

    struct Environment {
        let service: RangeSuggestionService
        let transport: FixtureTransport
        let model: LLMModel
    }

    /// Servicio con `FixtureTransport` (respuestas grabadas) y, si `configured`, Anthropic con clave y modelo.
    static func makeService(
        readings: any RangeReadingsSource,
        health: any HealthProfileReading = FakeHealthProfileReader(),
        provider: LLMProviderID = .anthropic,
        configured: Bool = true,
        replies: [FixtureTransport.Reply] = []
    ) async throws -> Environment {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        let keys = LLMKeyStore(itemFor: { items[$0]! })
        let defaults = UserDefaults(suiteName: "range-tests-\(UUID().uuidString)")!
        let settings = LLMSettingsStore(defaults: defaults)
        let model = LLMFixtures.model(for: provider)
        if configured {
            try await keys.save(LLMFixtures.testKey, for: provider)
            settings.setSelectedProvider(provider)
            settings.setSelectedModel(model)
        }
        let transport = FixtureTransport(replies)
        let registry = LLMProviderRegistry(transport: transport, log: RecordingLLMLogSink())
        let service = RangeSuggestionService(
            readings: readings, health: health, keys: keys, settings: settings,
            makeProvider: { registry.provider(for: $0) }, locale: "es-CO", clock: { now })
        return Environment(service: service, transport: transport, model: model)
    }

    static func reply(_ fixture: String, status: Int = 200) -> FixtureTransport.Reply {
        FixtureTransport.Reply(status: status, body: LLMFixtures.data(fixture))
    }
}
