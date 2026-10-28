import SwiftUI

/// "Datos usados y su fuente": lecturas propias (SQLite) y perfil de Salud (solo lectura), fila a fila.
struct RangeSuggestionDataSection: View {
    let suggestion: RangeSuggestion

    var body: some View {
        Section {
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.readings", defaultValue: "Lecturas propias"),
                value: String(localized: "range.suggest.data.readings.value",
                              defaultValue: "\(suggestion.readings.count) válidas · \(rounded(suggestion.readings.coverageHours)) h con datos"),
                source: readingsSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.percentiles", defaultValue: "Percentiles 5 y 95"),
                value: String(localized: "range.suggest.data.percentiles.value",
                              defaultValue: "\(rounded(suggestion.readings.percentile5)) y \(rounded(suggestion.readings.percentile95)) mg/dL"),
                source: readingsSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.meanSD", defaultValue: "Media y desviación"),
                value: String(localized: "range.suggest.data.meanSD.value",
                              defaultValue: "\(rounded(suggestion.readings.mean)) ± \(rounded(suggestion.readings.standardDeviation)) mg/dL"),
                source: readingsSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.age", defaultValue: "Edad"),
                value: suggestion.profile.ageYears.map { String(localized: "range.suggest.data.age.value", defaultValue: "\($0) años") },
                source: healthSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.sex", defaultValue: "Sexo biológico"),
                value: suggestion.profile.biologicalSex.map(sexText),
                source: healthSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.weight", defaultValue: "Peso"),
                value: suggestion.profile.weightKg.map { String(localized: "range.suggest.data.weight.value", defaultValue: "\($0.formatted(.number.precision(.fractionLength(1)))) kg") },
                source: healthSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.height", defaultValue: "Altura"),
                value: suggestion.profile.heightCm.map { String(localized: "range.suggest.data.height.value", defaultValue: "\(rounded($0)) cm") },
                source: healthSource)
            RangeSuggestionSourceRow(
                title: String(localized: "range.suggest.data.bmi", defaultValue: "IMC"),
                value: suggestion.profile.bodyMassIndex.map { $0.formatted(.number.precision(.fractionLength(1))) },
                source: String(localized: "range.suggest.source.computed", defaultValue: "Calculado con peso y altura de Salud"))
        } header: {
            Text(String(localized: "range.suggest.data", defaultValue: "Datos usados y su fuente"))
        } footer: {
            Text(String(localized: "range.suggest.data.footer", defaultValue: "La edad, el sexo, el peso y la altura no determinan un rango de glucosa validado: la personalización sale de tus propias lecturas. Lo que falta en Salud se omite."))
        }
    }

    private var readingsSource: String {
        String(localized: "range.suggest.source.readings", defaultValue: "Lecturas guardadas en este iPhone (últimos \(suggestion.readings.windowDays) días)")
    }

    private var healthSource: String {
        String(localized: "range.suggest.source.health", defaultValue: "Apple Salud, solo lectura")
    }

    private func sexText(_ sex: BiologicalSexSummary) -> String {
        switch sex {
        case .female: String(localized: "range.suggest.sex.female", defaultValue: "Femenino")
        case .male: String(localized: "range.suggest.sex.male", defaultValue: "Masculino")
        case .other: String(localized: "range.suggest.sex.other", defaultValue: "Otro")
        }
    }

    private func rounded(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
