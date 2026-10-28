import Foundation

/// Sugerencia fija y rotulada para `#Preview` y `-previewSensorState`: no lee SQLite, Salud ni red.
struct PreviewRangeSuggester: RangeSuggesting {
    var result: Result<RangeSuggestion, RangeSuggestionError> = .success(PreviewRangeSuggester.sample)
    var delay: Duration = .milliseconds(400)

    func suggest() async throws -> RangeSuggestion {
        try await Task.sleep(for: delay)
        return try result.get()
    }

    static let sample = RangeSuggestion(
        low: 75, high: 145,
        explanation: "Vista previa sintética. La línea baja parte del percentil 5 (74 mg/dL) y la alta del percentil 95 (146 mg/dL) de las lecturas simuladas, redondeadas a múltiplos de 5. La edad, el peso y la altura del perfil no fijan un rango validado: la personalización sale de las lecturas propias. Son líneas para leer la curva, no objetivos clínicos.",
        origin: .assistant(provider: .anthropic, modelName: "Vista previa"),
        readings: RangeSuggestion.ReadingSummary(count: 4_120, windowDays: 14, coverageHours: 68.7, first: Date.now.addingTimeInterval(-3 * 86_400),
                                 last: .now, percentile5: 74, percentile95: 146, median: 104, mean: 106.2, standardDeviation: 18.4),
        statisticalLow: 75, statisticalHigh: 145,
        profile: HealthProfile(ageYears: 41, biologicalSex: .male, weightKg: 78.5, heightCm: 176),
        healthNote: nil, assistantNote: nil)
}
