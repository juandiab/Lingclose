import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Insights de Hoy (T-23) sobre `PreviewData`: comidas sintéticas a las 07:30, 12:45 y 19:15 (Bogotá) con
/// una excursión de +62 mg/dL que alcanza el pico a los 50 min. Sin datos reales.
@MainActor
struct TodayInsightsTests {
    /// 2027-01-15 03:00 en Bogotá: la última comida (19:15) fue hace 7 h 45 min.
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(now: Date = Self.now) async -> TodayViewModel {
        let data = PreviewData(now: now, sensorState: .streaming)
        let model = TodayViewModel(dataSource: data, sensorSource: data, clock: { now })
        model.setVisibleLength(TodayPeriod.twentyFourHours.duration)
        await model.refresh()
        return model
    }

    @Test func mealResponseFindsTheSyntheticPeak() async throws {
        let model = await makeModel()
        let meals = model.marks.filter { $0.kind == .meal && $0.date < Self.now.addingTimeInterval(-3 * 3_600) }
        #expect(!meals.isEmpty)
        for meal in meals {
            let response = try #require(model.mealResponse(for: meal))
            // Excursión sintética de 62 mg/dL (± ruido y ritmo diurno) con pico hacia los 50 min.
            #expect((45...80).contains(response.rise))
            #expect((35 * 60...65 * 60).contains(response.timeToPeak))
            #expect((0...100).contains(response.score))
            #expect(response.mealAt == UTCInstant(meal.date))
            // Caché: misma respuesta sin recalcular.
            #expect(model.mealResponse(for: meal) == response)
            #expect(model.exerciseEffect(for: meal) == nil)
        }
    }

    @Test func recentMealHasNoResponseYet() async throws {
        // 07:50 en Bogotá: el desayuno de las 07:30 es de hace 20 min.
        let now = Date(timeIntervalSince1970: 1_800_000_000 + 4 * 3_600 + 50 * 60)
        let model = await makeModel(now: now)
        let breakfast = try #require(model.marks.last { $0.kind == .meal })
        #expect(now.timeIntervalSince(breakfast.date) < 3_600)
        #expect(model.mealResponse(for: breakfast) == nil)
        #expect(InsightFormat.notEnoughData(since: breakfast.date, now: now) == String(localized: "today.insight.meal.pending", defaultValue: "Sin datos suficientes todavía"))
    }

    @Test func insightsRowSummarisesTheVisibleDay() async throws {
        let model = await makeModel()
        let insights = try #require(model.insights)
        // La subida inicial de cada comida pasa de 2 mg/dL/min durante más de 10 min.
        #expect(insights.risingCount >= 1)
        #expect(insights.rateEvents.allSatisfy { $0.end >= UTCInstant(model.windowStart) && $0.start <= UTCInstant(model.windowEnd) })
        #expect(insights.meals.count >= 2)
        let best = try #require(insights.best)
        let worst = try #require(insights.worst)
        #expect(best.id != worst.id)
        #expect(best.response.score >= worst.response.score)
    }

    @Test func emptyInsightsAreHidden() {
        #expect(TodayInsights(rateEvents: [], meals: []).isEmpty)
    }

    @Test func mealSummaryText() {
        let samples = (-30...180).map { minute in
            let value: Double = switch minute {
            case ..<0: 100
            case 0...45: 100 + Double(minute) * 60 / 45
            case 46...110: 160 - Double(minute - 45) * 50 / 65
            default: 100
            }
            return BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: 1_800_000_000 + Int64(minute) * 60), valueMgdl: Int(value.rounded()))
        }
        let response = MealResponse(mealAt: UTCInstant(epochSeconds: 1_800_000_000), samples: samples, highReference: 180)
        #expect(response.map(InsightFormat.mealSummary) == String(localized: "today.insight.meal.summary", defaultValue: "Subió +\(60) mg/dL, pico a los \(45) min, volvió a los \(110) min"))
    }
}
