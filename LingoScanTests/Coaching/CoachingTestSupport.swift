import Foundation
import LingoCore
@testable import LingoScan

/// Datos sintéticos de T-25: una alerta alta tras una comida, servicio del asistente con Llavero y ajustes en memoria
/// y `FixtureTransport`. Ni clave real, ni red, ni datos reales.
enum CoachingFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let context = CoachingContext(kind: .high, value: 165, slopePerMinute: 1.4, minutesSinceLastMeal: 45,
                                         lastMealCarbsG: 72, minutesSinceLastExercise: 200, hour: 14, timeInRangeToday: 0.82)

    static func record(context: CoachingContext = context, openedAt: Date? = now) -> CoachingRecord {
        CoachingRecord(
            id: "lingoscan.alert.high.1800000000", context: context, tipIDs: CoachingRules.tips(for: context).map(\.id),
            mealNutrients: Nutrients(kcal: 640, carbsG: 72, proteinG: 24, fatG: 21), exerciseKind: "Correr",
            exerciseDurationMin: 30, createdAt: now, openedAt: openedAt)
    }

    struct Environment {
        let service: CoachingAssistantService
        let transport: FixtureTransport
    }

    static func makeService(provider: LLMProviderID = .anthropic, configured: Bool = true,
                            replies: [FixtureTransport.Reply] = []) async throws -> Environment {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        let keys = LLMKeyStore(itemFor: { items[$0]! })
        let settings = LLMSettingsStore(defaults: UserDefaults(suiteName: "coaching-tests-\(UUID().uuidString)")!)
        if configured {
            try await keys.save(LLMFixtures.testKey, for: provider)
            settings.setSelectedProvider(provider)
            settings.setSelectedModel(LLMFixtures.model(for: provider))
        }
        let transport = FixtureTransport(replies)
        let registry = LLMProviderRegistry(transport: transport, log: RecordingLLMLogSink())
        let service = CoachingAssistantService(keys: keys, settings: settings, makeProvider: { registry.provider(for: $0) },
                                               locale: "es-CO")
        return Environment(service: service, transport: transport)
    }

    static func reply(_ fixture: String, status: Int = 200) -> FixtureTransport.Reply {
        FixtureTransport.Reply(status: status, body: LLMFixtures.data(fixture))
    }

    static func store() -> CoachingStore {
        CoachingStore(defaults: UserDefaults(suiteName: "coaching-store-\(UUID().uuidString)")!)
    }
}

/// Lecturas, registro y diario en memoria para las alertas con consejos.
actor CoachingAlertStore: AlertDataStore {
    private(set) var samples: [BasicStats.Sample] = []
    var activity = CoachingActivity.none
    private(set) var activityRanges: [ClosedRange<UTCInstant>] = []

    func add(_ value: Int, at date: Date) { samples.append(BasicStats.Sample(measuredAt: UTCInstant(date), valueMgdl: value)) }
    func setActivity(_ activity: CoachingActivity) { self.activity = activity }

    func alertSamples(in range: ClosedRange<UTCInstant>) async throws -> [BasicStats.Sample] {
        samples.filter { range.contains($0.measuredAt) }.sorted { $0.measuredAt < $1.measuredAt }
    }

    func logAlert(_ level: EventLogLevel, _ message: LogMessage) async {}

    func coachingActivity(in range: ClosedRange<UTCInstant>) async -> CoachingActivity {
        activityRanges.append(range)
        return activity
    }
}
