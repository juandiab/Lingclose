import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Consejo en la notificación y tarjeta guardada (T-25), con lecturas y diario sintéticos.
struct CoachingAlertTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)  // 15-ene-2027 08:00 UTC
    static let utc = TimeZone(identifier: "UTC")!

    private func make(store: CoachingAlertStore, notifier: RecordingAlertNotifier, clock: HealthTestClock,
                      coaching: CoachingStore, includeTips: Bool = true) -> AlertService {
        let settingsStore = AlertSettingsStore(defaults: UserDefaults(suiteName: "CoachingAlertTests-\(UUID().uuidString)")!)
        settingsStore.saveSettings(AlertSettings(isEnabled: true, includeTips: includeTips))
        return AlertService(data: store, notifier: notifier, settingsStore: settingsStore, coachingStore: coaching,
                            thresholds: { (70, 140) }, now: { clock.now }, timeZone: { Self.utc })
    }

    @Test func highAfterMealCarriesTheWalkingTipAndSavesTheCard() async throws {
        let store = CoachingAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let coaching = CoachingFixtures.store()
        let service = make(store: store, notifier: notifier, clock: clock, coaching: coaching)
        await store.setActivity(CoachingActivity(
            lastMealAt: UTCInstant(Self.t0.addingTimeInterval(-40 * 60)), lastMealNutrients: Nutrients(kcal: 600, carbsG: 70)))
        await store.add(165, at: clock.now)

        await service.evaluate()

        let delivered = try #require(notifier.delivered.first)
        let walk = CoachingCatalog.walkAfterMeal.localizedBody
        #expect(delivered.title.contains("165"))
        #expect(delivered.body.hasSuffix("\n" + walk), "el primer consejo va al final del cuerpo")
        let record = try #require(coaching.latest())
        #expect(delivered.coachingID == record.id)
        #expect(record.id == delivered.id)
        #expect(record.tipIDs == ["walkAfterMeal", "waterNoSugar"])
        #expect(record.context.minutesSinceLastMeal == 40)
        #expect(record.context.lastMealCarbsG == 70)
        #expect(record.context.hour == 8)
        #expect(record.mealNutrients?.kcal == 600)
        #expect(record.openedAt == nil, "la tarjeta espera a que se toque la notificación")
        // La actividad se busca desde el inicio del día local o 6 h antes, lo que sea antes.
        let range = try #require(await store.activityRanges.first)
        #expect(range.lowerBound == UTCInstant(Self.t0.addingTimeInterval(-8 * 3600)))
    }

    @Test func tipsOffSendsThePlainAlertAndNoCard() async throws {
        let store = CoachingAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let coaching = CoachingFixtures.store()
        let service = make(store: store, notifier: notifier, clock: clock, coaching: coaching, includeTips: false)
        await store.add(165, at: clock.now)
        await service.evaluate()
        let delivered = try #require(notifier.delivered.first)
        #expect(!delivered.body.contains("\n"))
        #expect(delivered.coachingID == nil)
        #expect(coaching.latest() == nil)
        #expect(await store.activityRanges.isEmpty, "sin consejos no se lee el diario")
    }

    @Test func lowPutsTheSymptomsTipFirst() async throws {
        let store = CoachingAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: store, notifier: notifier, clock: clock, coaching: CoachingFixtures.store())
        await store.add(62, at: clock.now)
        await service.evaluate()
        #expect(notifier.delivered.first?.body.hasSuffix(CoachingCatalog.lowSymptoms.localizedBody) == true)
    }

    @Test func testNotificationShowsATipWhenEnabled() async throws {
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0)
        let service = make(store: CoachingAlertStore(), notifier: notifier, clock: clock, coaching: CoachingFixtures.store())
        #expect(await service.sendTest())
        #expect(notifier.delivered.first?.body.hasSuffix(CoachingCatalog.walkAfterMeal.localizedBody) == true)
    }

    @Test func newAlertReplacesTheDismissedCard() async throws {
        let coaching = CoachingFixtures.store()
        var old = CoachingFixtures.record()
        old.isDismissed = true
        coaching.save(old)
        let store = CoachingAlertStore()
        let notifier = RecordingAlertNotifier()
        let clock = HealthTestClock(Self.t0.addingTimeInterval(3600))
        let service = make(store: store, notifier: notifier, clock: clock, coaching: coaching)
        await store.add(60, at: clock.now)
        await service.evaluate()
        let record = try #require(coaching.latest())
        #expect(record.id != old.id)
        #expect(!record.isDismissed)
        #expect(record.context.kind == .low)
    }
}

/// Contexto, actividad del diario y tarjeta persistida.
struct CoachingContextTests {
    static let at = UTCInstant(epochSeconds: 1_800_000_000)

    private func event(_ kind: DiaryEventKind, minutesAgo: Int, duration: Int? = nil, carbs: Double? = nil,
                       text: String? = nil, deleted: Bool = false) -> DiaryEvent {
        let instant = Self.at.adding(seconds: Int64(-minutesAgo * 60))
        return DiaryEvent(eventID: "e-\(kind.rawValue)-\(minutesAgo)", kind: kind, at: instant, tz: "UTC", durationMin: duration,
                          carbsG: carbs, text: text, createdAt: instant, updatedAt: instant, editID: "x-\(minutesAgo)",
                          editedByAppID: "test", deleted: deleted, synthetic: false)
    }

    @Test func activityTakesTheLatestMealAndExerciseEnd() {
        let events = [
            event(.meal, minutesAgo: 300, carbs: 20), event(.meal, minutesAgo: 50, carbs: 55, text: "Arepa con queso"),
            event(.meal, minutesAgo: 10, deleted: true), event(.meal, minutesAgo: -20, carbs: 99),
            event(.exercise, minutesAgo: 120, duration: 90, text: "Correr · 5,2 km"), event(.exercise, minutesAgo: 60, duration: 10),
            event(.note, minutesAgo: 5, text: "nota privada"),
        ]
        let activity = CoachingActivity.from(events, now: Self.at, nutrients: { _ in nil },
                                             workoutKind: { $0.durationMin == 90 ? "Correr" : nil })
        #expect(activity.lastMealAt == Self.at.adding(seconds: -50 * 60))
        #expect(activity.lastMealNutrients == Nutrients(carbsG: 55))
        // 120 min antes + 90 min = terminó hace 30 min; el de 10 min terminó hace 50.
        #expect(activity.lastExerciseEnd == Self.at.adding(seconds: -30 * 60))
        #expect(activity.lastExerciseKind == "Correr")
        #expect(activity.lastExerciseDurationMin == 90)
    }

    @Test func contextUsesActivityHourAndTimeInRange() {
        let samples = (0..<60).map { BasicStats.Sample(measuredAt: Self.at.adding(seconds: Int64(-$0 * 60)), valueMgdl: $0 < 15 ? 165 : 100) }
        let event = AlertEvent(kind: .high, at: Self.at, value: 165, slopePerMinute: 2.2, since: Self.at)
        let activity = CoachingActivity(lastMealAt: Self.at.adding(seconds: -45 * 60), lastMealNutrients: Nutrients(carbsG: 60),
                                        lastExerciseEnd: Self.at.adding(seconds: -200 * 60))
        let bogota = TimeZone(identifier: "America/Bogota")!
        let context = CoachingContextBuilder.context(for: event, activity: activity, daySamples: samples, low: 70, high: 140,
                                                     timeZone: bogota)
        #expect(context.hour == 3)  // 08:00 UTC = 03:00 en Bogotá
        #expect(context.minutesSinceLastMeal == 45)
        #expect(context.lastMealCarbsG == 60)
        #expect(context.minutesSinceLastExercise == 200)
        #expect(context.timeInRangeToday == 0.75)
        #expect(CoachingContextBuilder.timeInRange(Array(samples.prefix(10)), low: 70, high: 140) == nil, "pocas lecturas")
    }

    @Test func cardIsVisibleOnlyAfterOpeningUntilDismissedOrStale() {
        let store = CoachingFixtures.store()
        let record = CoachingFixtures.record(openedAt: nil)
        store.save(record)
        let now = CoachingFixtures.now
        #expect(store.latest()?.isVisible(at: now) == false)
        store.markOpened(id: "otra", at: now)
        #expect(store.latest()?.openedAt == nil, "solo la notificación de esta alerta la abre")
        store.markOpened(id: record.id, at: now)
        #expect(store.latest()?.isVisible(at: now.addingTimeInterval(60)) == true)
        #expect(store.latest()?.isVisible(at: now.addingTimeInterval(CoachingRecord.maxAge + 1)) == false)
        store.dismiss(id: record.id)
        #expect(store.latest()?.isVisible(at: now) == false)
    }

    @Test func tipsResolveToTranslatedOrDefaultText() {
        for tip in CoachingCatalog.all {
            #expect(!tip.localizedTitle.isEmpty && tip.localizedTitle != tip.titleKey)
            #expect(!tip.localizedBody.isEmpty && tip.localizedBody != tip.bodyKey)
        }
    }
}

/// Hoja del asistente: una petición, "Guardar como nota" y errores claros.
@MainActor
struct CoachingAssistantViewModelTests {
    @Test func answerCanBeSavedOnceAsADiaryNote() async throws {
        let diary = InMemoryDiaryStore()
        let model = CoachingAssistantViewModel(
            record: CoachingFixtures.record(), assistant: PreviewCoachingAssistant(delay: .zero), diary: diary,
            timeZone: TimeZone(identifier: "UTC")!, now: { CoachingFixtures.now }, newID: { UUID().uuidString })
        await model.load()
        #expect(model.answer != nil)
        #expect(await model.saveNote())
        #expect(model.noteState == .saved)
        #expect(await model.saveNote() == false, "una sola nota por respuesta")
        let notes = try await diary.events(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 2_000_000_000))
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.kind == .note)
        #expect(note.at == UTCInstant(CoachingFixtures.now))
        #expect(note.text?.contains(PreviewCoachingAssistant.sample.summary) == true)
        #expect(note.text?.contains("• Pausa activa:") == true)
        #expect(!note.synthetic && note.parentEditID == nil)
    }

    @Test func failedSaveIsReported() async throws {
        let diary = InMemoryDiaryStore()
        await diary.setFailNextSave(true)
        let model = CoachingAssistantViewModel(record: CoachingFixtures.record(), assistant: PreviewCoachingAssistant(delay: .zero),
                                               diary: diary)
        await model.load()
        #expect(await model.saveNote() == false)
        #expect(model.noteState == .failed)
    }

    @Test func providerErrorIsShownWithoutRetry() async throws {
        let env = try await CoachingFixtures.makeService(replies: [CoachingFixtures.reply("anthropic-429", status: 429)])
        let model = CoachingAssistantViewModel(record: CoachingFixtures.record(), assistant: env.service, diary: InMemoryDiaryStore())
        await model.load()
        await model.load()
        #expect(model.phase == .failed(LLMError.rateLimited.description))
        #expect(env.transport.requests.count == 1)
    }

    @Test func insulinReplyEndsInAClearError() async throws {
        let env = try await CoachingFixtures.makeService(replies: [CoachingFixtures.reply("anthropic-coach-insulin")])
        let model = CoachingAssistantViewModel(record: CoachingFixtures.record(), assistant: env.service, diary: InMemoryDiaryStore())
        await model.load()
        guard case .failed(let message) = model.phase else {
            Issue.record("debería fallar")
            return
        }
        #expect(!message.isEmpty)
        #expect(model.answer == nil)
    }
}
