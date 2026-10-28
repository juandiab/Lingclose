import Testing
@testable import LingoCore

struct AnalyticsMealResponseTests {
    private typealias S = AnalyticsSeries

    /// Comida en el minuto 0: base 100 durante 30 min previos, pico 160 a los 45 min, de vuelta a 110 a los 110 min
    /// y estable en 100 hasta las 3 h.
    private var meal: [BasicStats.Sample] {
        S.series(-30...180) { m in
            switch m {
            case ..<0: 100
            case 0...45: 100 + Double(m) * 60 / 45
            case 46...110: 160 - Double(m - 45) * 50 / 65
            default: 100
            }
        }
    }

    @Test func peakRiseAndReturn() throws {
        let response = try #require(MealResponse(mealAt: S.t0, samples: meal, highReference: 140))
        #expect(response.baseline == 100)
        #expect(response.peakValue == 160)
        #expect(response.peakAt == S.instant(45))
        #expect(response.rise == 60)
        #expect(response.timeToPeak == 45 * 60)
        #expect(response.returnedAt == S.instant(110))
        #expect(response.timeToReturn == Int64(110 * 60))
        // Por encima de 140: minutos 31…45 de la subida y 46…70 de la bajada (40 lecturas de 1 min).
        #expect(response.timeAboveHigh == 40 * 60)
        // 100 − (60 − 20) × 0,6 − (110 − 60) / 3 = 59,33.
        #expect(response.score == 59)
    }

    @Test func noReadingsMeansNoResponse() {
        #expect(MealResponse(mealAt: S.t0, samples: [], highReference: 140) == nil)
    }

    @Test func recentMealWithLessThanAnHourIsNil() {
        let partial = meal.filter { $0.measuredAt <= S.instant(50) }
        #expect(MealResponse(mealAt: S.t0, samples: partial, highReference: 140) == nil)
    }

    @Test func gapInTheFirstHourIsNil() {
        let holed = meal.filter { !(S.instant(10)...S.instant(35)).contains($0.measuredAt) }
        #expect(MealResponse(mealAt: S.t0, samples: holed, highReference: 140) == nil)
        // Un hueco de 15 min sí se tolera.
        let small = meal.filter { !(S.instant(10)...S.instant(24)).contains($0.measuredAt) }
        #expect(MealResponse(mealAt: S.t0, samples: small, highReference: 140) != nil)
    }

    @Test func noReturnWithinThreeHours() throws {
        let stuck = S.series(-30...180) { m in m < 0 ? 100 : min(170, 100 + Double(m)) }
        let response = try #require(MealResponse(mealAt: S.t0, samples: stuck, highReference: 140))
        #expect(response.returnedAt == nil)
        #expect(response.rise == 70)
        // (70 − 20) × 0,6 = 30; sin vuelta, −40.
        #expect(response.score == 30)
    }

    @Test func baselineFallsBackToFirstReadingAfterTheMeal() throws {
        let noBefore = meal.filter { $0.measuredAt >= S.t0 }
        let response = try #require(MealResponse(mealAt: S.t0, samples: noBefore, highReference: 140))
        #expect(response.baseline == 100)
    }

    @Test func scoreBounds() {
        #expect(MealResponse.score(rise: 10, minutesToReturn: 30) == 100)
        #expect(MealResponse.score(rise: 300, minutesToReturn: nil) == 0)
    }
}
