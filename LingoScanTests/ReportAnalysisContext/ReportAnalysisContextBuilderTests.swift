import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// Contexto opcional del análisis (T-33): comidas unidas por `at` con el snapshot compactado, nombres limpios, sin ids
/// ni supuestos, topes, recorte por tamaño y `nil` con todo apagado.
struct ReportAnalysisContextBuilderTests {
    private typealias F = ReportAnalysisContextFixtures
    private let all = ReportAnalysisSharing(meals: true, sleepActivity: true, profile: true)

    private func json(_ context: ReportAnalysisContext?) throws -> String {
        let context = try #require(context)
        return String(data: try context.jsonData(), encoding: .utf8)!
    }

    @Test func everythingOffGivesNil() {
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents()
        let records = Dictionary(uniqueKeysWithValues: events.filter { $0.kind == .meal }.map { ($0.eventID, F.record(for: $0)) })
        let context = ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: events, nutrition: records, sleep: F.nights(3), steps: F.steps(3),
            profile: F.profile, body: F.body(), sharing: .none)
        #expect(context == nil)
        // Encendido pero sin nada que enviar: también `nil`.
        let empty = ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: [], nutrition: [:], sleep: [], steps: [], profile: nil, sharing: all)
        #expect(empty == nil)
    }

    @Test func mealsAreJoinedByTimeOnlyWithTheCompactedSnapshot() throws {
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents()
        let snapshot = bundle.snapshot.compact()
        // Una comida fuera del período (no está en el snapshot) con registro: no debe ir.
        let outside = ReportAnalysisFixtures.event(.meal, at: bundle.period.end.adding(seconds: 86_400), carbs: 10, text: "Fuera")
        var meals = events.filter { $0.kind == .meal }
        meals.append(outside)
        let records = Dictionary(uniqueKeysWithValues: meals.map { ($0.eventID, F.record(for: $0)) })
        let context = try #require(ReportAnalysisContextBuilder.build(
            snapshot: snapshot, events: events + [outside], nutrition: records, sleep: [], steps: [], profile: nil,
            sharing: ReportAnalysisSharing(meals: true)))
        let contextMeals = try #require(context.meals)
        #expect(contextMeals.map(\.at) == snapshot.meals.meals.map(\.at))
        #expect(!contextMeals.contains { $0.at == outside.at })
        let first = try #require(contextMeals.first)
        #expect(first.name == F.mealName)
        #expect(first.kcal == 642.3 && first.carbsG == 80 && first.proteinG == 32 && first.fatG == 17.5)
        #expect(first.source == "assistant" && first.kind == "food")
        #expect(context.sleep == nil && context.activity == nil && context.profile == nil)

        // Si `compact()` quitó las comidas, no va contexto de comidas.
        let stripped = bundle.snapshot.compact(maxBytes: 1)
        #expect(stripped.meals.meals.isEmpty)
        #expect(ReportAnalysisContextBuilder.build(
            snapshot: stripped, events: events, nutrition: records, sleep: [], steps: [], profile: nil,
            sharing: ReportAnalysisSharing(meals: true)) == nil)
    }

    @Test func jsonCarriesNoIdsAssumptionsOrConfidence() throws {
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents()
        let meals = events.filter { $0.kind == .meal }
        let records = Dictionary(uniqueKeysWithValues: meals.map { ($0.eventID, F.record(for: $0)) })
        let text = try json(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: events, nutrition: records, sleep: F.nights(2), steps: F.steps(2),
            profile: F.profile, body: F.body(), sharing: all))
        for event in events { #expect(!text.contains(event.eventID)) }
        for forbidden in ["SUPUESTO-INVENTADO", "assumptions", "event_id", "confidence", "modelo-inventado", "anthropic",
                          "America/Bogota", ReportAnalysisFixtures.freeText] {
            #expect(!text.contains(forbidden), "no debería llevar \(forbidden)")
        }
        #expect(text.contains("\"name\":\"\(F.mealName)\""))
    }

    @Test func nameFallsBackToTheEventTextTrimmedToOneLine() throws {
        let long = "Sopa de verduras\ncon\tpan y queso " + String(repeating: "muy larga ", count: 20)
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents(mealText: long)
        let context = try #require(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: events, nutrition: [:], sleep: [], steps: [], profile: nil,
            sharing: ReportAnalysisSharing(meals: true)))
        let name = try #require(context.meals?.first?.name)
        #expect(name.count <= ReportAnalysisContextBuilder.maxNameLength)
        #expect(!name.contains("\n") && !name.contains("\t") && !name.contains("  "))
        #expect(name.hasPrefix("Sopa de verduras con pan y queso"))
        // Sin registro: sin nutrientes, sin fuente ni tipo.
        let meal = try #require(context.meals?.first)
        #expect(meal.kcal == nil && meal.source == nil && meal.kind == nil)

        // Registro sin nombre: usa el texto del evento; nombre vacío y sin texto ni nutrientes: la comida no va.
        let event = events.first { $0.kind == .meal }!
        let unnamed = F.record(for: event, name: "   ", source: .label(provider: "p", model: "m"), kind: .nutritionLabel)
        let withRecord = try #require(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: events, nutrition: [event.eventID: unnamed], sleep: [], steps: [],
            profile: nil, sharing: ReportAnalysisSharing(meals: true)))
        let labelled = try #require(withRecord.meals?.first { $0.at == event.at })
        #expect(labelled.name?.hasPrefix("Sopa de verduras") == true)
        #expect(labelled.source == "label" && labelled.kind == "nutrition_label")
        #expect(ReportAnalysisContextBuilder.cleanName(" \n\t ") == nil)
    }

    @Test func listsAreCappedToTheLatest() throws {
        let (bundle, _) = ReportAnalysisFixtures.bundleWithEvents(withDiary: false)
        let context = try #require(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: [], nutrition: [:], sleep: Array(F.nights(40).reversed()),
            steps: F.steps(40) + [DailySteps(day: "2026-01-01", steps: 0)], profile: nil,
            sharing: ReportAnalysisSharing(sleepActivity: true)))
        let nights = try #require(context.sleep)
        #expect(nights.count == ReportAnalysisContextBuilder.maxNights)
        #expect(nights.map(\.night) == F.nights(40).suffix(31).map(\.night))
        let days = try #require(context.activity?.dailySteps)
        #expect(days.count == ReportAnalysisContextBuilder.maxStepDays)
        #expect(days.last?.day == F.steps(40).last?.day)
        #expect(!days.contains { $0.steps == 0 })
    }

    @Test func trimsBySizeInTheDesignedOrder() throws {
        let at = UTCInstant(epochSeconds: 1_800_000_000)
        let meals = (0..<200).map { i in
            ReportAnalysisMealContext(at: at.adding(seconds: Int64(i) * 3_600), name: String(repeating: "x", count: 60),
                                      kcal: 500, carbsG: 60, proteinG: 20, fatG: 15, source: "manual", kind: "food")
        }
        let context = ReportAnalysisContext(meals: meals, sleep: F.nights(31),
                                            activity: ReportAnalysisActivityContext(dailySteps: F.steps(31)), profile: nil)
        #expect(context.jsonByteCount > ReportAnalysisContextBuilder.maxBytes)

        let trimmed = ReportAnalysisContextBuilder.trimmed(context)
        #expect(trimmed.jsonByteCount <= ReportAnalysisContextBuilder.maxBytes)
        #expect(trimmed.sleep?.count == ReportAnalysisContextBuilder.trimmedNights)
        #expect(trimmed.meals?.count == ReportAnalysisContextBuilder.trimmedMeals)
        #expect(trimmed.meals?.last == meals.last)
        // Los pasos solo se recortan si después de sueño y comidas aún no cabe.
        #expect(trimmed.activity?.dailySteps.count == 31)

        let tight = ReportAnalysisContextBuilder.trimmed(context, maxBytes: 100)
        #expect(tight.activity?.dailySteps.count == ReportAnalysisContextBuilder.trimmedStepDays)
        #expect(tight.activity?.dailySteps.last == F.steps(31).last)

        let small = ReportAnalysisContext(meals: Array(meals.prefix(3)), sleep: F.nights(20), activity: nil, profile: nil)
        #expect(ReportAnalysisContextBuilder.trimmed(small) == small)
    }

    @Test func profileCarriesBodyCompositionAndTrend() throws {
        let (bundle, _) = ReportAnalysisFixtures.bundleWithEvents(withDiary: false)
        let context = try #require(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: [], nutrition: [:], sleep: [], steps: [], profile: F.profile,
            body: F.body(), sharing: ReportAnalysisSharing(profile: true)))
        let profile = try #require(context.profile)
        #expect(profile.ageYears == 40 && profile.sex == "male" && profile.heightCm == 175)
        // El peso y el IMC de la báscula mandan sobre los del perfil.
        #expect(profile.weightKg == 69.5)
        #expect(profile.bmi == 22.7)
        #expect(profile.bodyFatPct == 21.3 && profile.leanMassKg == 54.6 && profile.waistCm == 82)
        let trend = try #require(profile.bodyTrend)
        #expect(trend.map(\.metric) == ["weight_kg", "body_fat_pct"])
        #expect(trend.first?.first.value == 70.7 && trend.first?.last.value == 69.5)
        #expect(trend.first?.first.day != trend.first?.last.day)
        let text = try json(context)
        #expect(text.contains("\"body_trend\"") && text.contains("\"lean_mass_kg\":54.6"))
    }

    @Test func profileWithoutScaleHasNoBodyFieldsNorTrend() throws {
        let (bundle, _) = ReportAnalysisFixtures.bundleWithEvents(withDiary: false)
        let context = try #require(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: [], nutrition: [:], sleep: [], steps: [], profile: F.profile,
            body: .empty, sharing: ReportAnalysisSharing(profile: true)))
        let profile = try #require(context.profile)
        #expect(profile.weightKg == 70)
        #expect(profile.bmi == 22.9) // calculado: 70,04 / 1,75²
        #expect(profile.bodyFatPct == nil && profile.leanMassKg == nil && profile.waistCm == nil && profile.bodyTrend == nil)
        #expect(!(try json(context)).contains("body_trend"))
        // Sin perfil ni báscula: sin bloque.
        #expect(ReportAnalysisContextBuilder.build(
            snapshot: bundle.snapshot.compact(), events: [], nutrition: [:], sleep: [], steps: [], profile: .empty,
            body: .empty, sharing: ReportAnalysisSharing(profile: true)) == nil)
    }

    @Test func bodyTrendNeedsTwoSamplesThreeDaysApart() {
        let day0 = Date(timeIntervalSince1970: 1_799_500_000)
        let close = BodyComposition.make(
            latest: [:], inPeriod: [.weight: [BodyMeasurement(date: day0, value: 70), BodyMeasurement(date: day0.addingTimeInterval(2 * 86_400), value: 69)]],
            timeZone: ReportAnalysisFixtures.bogota)
        #expect(close.trends.isEmpty)
        let apart = BodyComposition.make(
            latest: [:], inPeriod: [.weight: [BodyMeasurement(date: day0.addingTimeInterval(3 * 86_400), value: 69),
                                              BodyMeasurement(date: day0, value: 70)]],
            timeZone: ReportAnalysisFixtures.bogota)
        #expect(apart.trends.count == 1)
        #expect(apart.trends.first?.first.value == 70 && apart.trends.first?.last.value == 69)
        #expect(BodyComposition.make(latest: [:], inPeriod: [:], timeZone: .gmt).isEmpty)
    }

    @Test func gapsListEnabledBlocksWithoutData() {
        let context = ReportAnalysisContext(meals: nil, sleep: F.nights(1), activity: nil, profile: nil)
        #expect(ReportAnalysisContext.gaps(in: context, sharing: ReportAnalysisSharing(meals: true, sleepActivity: true, profile: true))
                == [.meals, .steps, .profile])
        #expect(ReportAnalysisContext.gaps(in: nil, sharing: .none).isEmpty)
    }
}
