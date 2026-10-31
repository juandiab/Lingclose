/// Reporte 4 — respuesta a comidas (T-27a). Informativo, no médico.
///
/// Por cada comida del período, `MealResponse` (referencia alta = `rangeHigh`): subida, pico, tiempo al pico,
/// minutos hasta volver, tiempo sobre el rango y puntuación. `response == nil` si `MealResponse` no tiene datos
/// suficientes (menos de 1 h de lecturas tras la comida, hueco > 20 min en la primera hora o sin línea base).
/// `overlapsPreviousMeal` marca comidas con otra en las 3 h anteriores (sus curvas se mezclan).
/// Agregados globales, por franja (`TimeOfDaySlot`) y por tramo de carbohidratos (`CarbBucket`).
/// Mínimo: un agregado necesita ≥ `ReportThresholds.minimumEventsPerGroup` (3) comidas con respuesta; con
/// menos, sus medias son `nil` (los conteos se dan siempre).
public struct MealResponseReport: Sendable, Hashable, Codable {
    public struct Response: Sendable, Hashable, Codable {
        public let baseline: Double
        public let peak: Int
        public let rise: Double
        public let timeToPeakMinutes: Int
        /// `nil` si no volvió a línea base + 10 mg/dL en 3 h.
        public let returnMinutes: Int?
        public let timeAboveRangeMinutes: Int
        public let score: Int

        init(_ r: MealResponse) {
            baseline = ReportRounding.r1(r.baseline)
            peak = r.peakValue
            rise = ReportRounding.r1(r.rise)
            timeToPeakMinutes = Int(r.timeToPeak / 60)
            returnMinutes = r.timeToReturn.map { Int($0 / 60) }
            timeAboveRangeMinutes = Int(r.timeAboveHigh / 60)
            score = r.score
        }

        enum CodingKeys: String, CodingKey {
            case baseline, peak, rise
            case timeToPeakMinutes = "time_to_peak_min"
            case returnMinutes = "return_min"
            case timeAboveRangeMinutes = "time_above_range_min"
            case score
        }
    }

    public struct Meal: Sendable, Hashable, Codable {
        public let at: UTCInstant
        /// Minuto local desde la medianoche.
        public let localMinute: Int
        public let slot: TimeOfDaySlot
        public let carbsG: Double?
        public let carbBucket: CarbBucket
        public let overlapsPreviousMeal: Bool
        public let response: Response?

        enum CodingKeys: String, CodingKey {
            case at
            case localMinute = "local_minute"
            case slot
            case carbsG = "carbs_g"
            case carbBucket = "carb_bucket"
            case overlapsPreviousMeal = "overlaps_previous"
            case response
        }
    }

    public struct Stats: Sendable, Hashable, Codable {
        public let meals: Int
        public let analyzed: Int
        public let meanRise: Double?
        public let medianRise: Double?
        public let meanPeak: Double?
        public let meanTimeToPeakMinutes: Double?
        public let meanScore: Double?
        /// Fracción 0…1 de comidas analizadas que volvieron a línea base en 3 h.
        public let returnedFraction: Double?

        public var isReliable: Bool { analyzed >= ReportThresholds.minimumEventsPerGroup }

        init(_ meals: [Meal]) {
            let responses = meals.compactMap(\.response)
            self.meals = meals.count
            analyzed = responses.count
            guard responses.count >= ReportThresholds.minimumEventsPerGroup else {
                meanRise = nil; medianRise = nil; meanPeak = nil; meanTimeToPeakMinutes = nil
                meanScore = nil; returnedFraction = nil
                return
            }
            meanRise = ReportRounding.r1(optional: ReportRounding.mean(responses.map(\.rise)))
            medianRise = ReportRounding.r1(optional: ReportRounding.median(responses.map(\.rise)))
            meanPeak = ReportRounding.r1(optional: ReportRounding.mean(responses.map { Double($0.peak) }))
            meanTimeToPeakMinutes = ReportRounding.r1(optional: ReportRounding.mean(responses.map { Double($0.timeToPeakMinutes) }))
            meanScore = ReportRounding.r1(optional: ReportRounding.mean(responses.map { Double($0.score) }))
            returnedFraction = ReportRounding.r3(Double(responses.filter { $0.returnMinutes != nil }.count) / Double(responses.count))
        }

        enum CodingKeys: String, CodingKey {
            case meals, analyzed
            case meanRise = "mean_rise"
            case medianRise = "median_rise"
            case meanPeak = "mean_peak"
            case meanTimeToPeakMinutes = "mean_time_to_peak_min"
            case meanScore = "mean_score"
            case returnedFraction = "returned_fraction"
        }
    }

    public internal(set) var meals: [Meal]
    public let overall: Stats
    public let bySlot: [ReportGroup<TimeOfDaySlot, Stats>]
    public let byCarbs: [ReportGroup<CarbBucket, Stats>]

    public var hasEnoughData: Bool { overall.analyzed > 0 }

    enum CodingKeys: String, CodingKey {
        case meals, overall
        case bySlot = "by_slot"
        case byCarbs = "by_carbs"
    }

    init(context: ReportContext) {
        let all = context.allMeals
        var result: [Meal] = []
        for (index, event) in all.enumerated() where context.period.contains(event.at) {
            let t = event.at.epochSeconds
            let window = context.range(from: t - 2 * MealResponse.baselineWindow, to: t + MealResponse.horizon + 1)
            let response = MealResponse(mealAt: event.at, samples: context.samples(window),
                                        highReference: context.configuration.rangeHigh)
            let overlaps = index > 0 && t - all[index - 1].at.epochSeconds < ReportThresholds.mealOverlapSeconds
            let minute = context.clock.minuteOfDay(t)
            result.append(Meal(at: event.at, localMinute: minute, slot: TimeOfDaySlot(minuteOfDay: minute),
                               carbsG: event.carbsG, carbBucket: CarbBucket(carbsG: event.carbsG),
                               overlapsPreviousMeal: overlaps, response: response.map(Response.init)))
        }
        meals = result
        overall = Stats(result)
        bySlot = TimeOfDaySlot.allCases.map { slot in ReportGroup(key: slot, stats: Stats(result.filter { $0.slot == slot })) }
        byCarbs = CarbBucket.allCases.map { bucket in
            ReportGroup(key: bucket, stats: Stats(result.filter { $0.carbBucket == bucket }))
        }
    }
}
