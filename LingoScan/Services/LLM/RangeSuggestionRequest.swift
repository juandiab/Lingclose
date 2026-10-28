import Foundation

/// Lo único que sale del teléfono al pedir un rango de referencia: cifras agregadas de las lecturas
/// propias y, si Salud los tiene, edad, sexo biológico e IMC. Nunca lecturas crudas, fechas, series,
/// identificadores de sesión ni de sensor. `locale` solo elige el idioma de la explicación.
struct RangeSuggestionRequest: Sendable, Equatable {
    var windowDays: Int
    var readingCount: Int
    var coverageHours: Double
    var percentile5: Double
    var percentile95: Double
    var median: Double
    var mean: Double
    var standardDeviation: Double
    /// Propuesta estadística ya acotada (`RangeSuggestionPolicy`), para que el modelo parta de ella.
    var statisticalLow: Int
    var statisticalHigh: Int
    var ageYears: Int?
    /// `female`, `male` u `other`; `nil` si Salud no lo tiene.
    var biologicalSex: String?
    var bodyMassIndex: Double?
    var locale: String

    /// Texto del mensaje del usuario: las cifras agregadas como JSON legible. Lo que falta va como `null`.
    var userText: String {
        func num(_ value: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) }
        func opt(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        let profile = """
          "profile": {
            "age_years": \(ageYears.map(String.init) ?? "null"),
            "biological_sex": \(opt(biologicalSex)),
            "bmi": \(bodyMassIndex.map(num) ?? "null")
          }
        """
        return """
        Cifras agregadas de las lecturas propias (no hay lecturas individuales):
        {
          "window_days": \(windowDays),
          "reading_count": \(readingCount),
          "coverage_hours": \(num(coverageHours)),
          "glucose_mgdl": {
            "p5": \(num(percentile5)),
            "p95": \(num(percentile95)),
            "median": \(num(median)),
            "mean": \(num(mean)),
            "sd": \(num(standardDeviation))
          },
          "statistical_proposal": { "low_mgdl": \(statisticalLow), "high_mgdl": \(statisticalHigh) },
        \(profile)
        }
        """
    }
}
