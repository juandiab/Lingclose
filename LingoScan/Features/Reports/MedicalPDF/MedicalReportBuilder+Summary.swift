import Foundation
import LingoCore

extension MedicalReportBuilder {
    typealias S = MedicalReportStrings

    /// "Datos del paciente": nombre y lo que Apple Salud tenga. Lo que falta dice "No disponible en Apple Salud".
    static func patientFacts(_ input: MedicalReportInput, name: String, _ f: MedicalReportFormatter) -> [MedicalFact] {
        let profile = input.profile
        func fact(_ label: String, _ value: String?) -> MedicalFact {
            MedicalFact(label: label, value: value ?? S.unavailable, isAvailable: value != nil)
        }
        var facts = [MedicalFact(label: S.name, value: name.isEmpty ? S.noName : name, isAvailable: !name.isEmpty)]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = f.timeZone
        let age = profile.birthDate.flatMap { calendar.dateComponents([.year], from: $0, to: input.generatedAt).year }
            ?? profile.ageYears
        if let birth = profile.birthDate {
            let text = f.longDate(birth)
            facts.append(fact(S.birthDate, age.map { "\(text) (\(S.years($0)))" } ?? text))
        } else if let age {
            facts.append(fact(S.age, S.years(age)))
        } else {
            facts.append(fact(S.birthDate, nil))
        }
        facts.append(fact(S.sex, profile.biologicalSex.map(sexName)))
        facts.append(fact(S.bloodType, profile.bloodType?.rawValue))
        facts.append(fact(S.height, profile.heightCm.map { "\(f.flexible($0)) cm" }))

        let weight = input.body.latest[.weight] ?? profile.weightKg
        facts.append(fact(S.weight, weight.map { "\(f.number($0, decimals: 1)) kg" }))
        if let trend = input.body.trends.first(where: { $0.metric == BodyMetric.weight.rawValue }) {
            let delta = trend.last.value - trend.first.value
            let text = "\(f.signed(delta, decimals: 1)) kg (\(f.number(trend.first.value, decimals: 1)) → \(f.number(trend.last.value, decimals: 1)) kg)"
            facts.append(fact(S.weightChange, text))
        }
        var bmi = input.body.latest[.bmi] ?? profile.bodyMassIndex
        if bmi == nil, let weight, let height = profile.heightCm, height > 0 {
            bmi = weight / ((height / 100) * (height / 100))
        }
        facts.append(fact(S.bmi, bmi.map { "\(f.number($0, decimals: 1)) kg/m²" }))
        return facts
    }

    static func sexName(_ sex: BiologicalSexSummary) -> String {
        switch sex {
        case .female: S.female
        case .male: S.male
        case .other: S.otherSex
        }
    }

    /// Período, días con datos, sensor, tiempo con sensor activo y número de lecturas (sin número de serie).
    static func periodFacts(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> [MedicalFact] {
        let stats = bundle.summary.stats
        return [
            MedicalFact(label: S.period, value: f.periodRange(bundle.period)),
            MedicalFact(label: S.daysLabel, value: S.daysOf(bundle.summary.daysWithData, of: bundle.dayCount)),
            MedicalFact(label: S.sensor, value: S.sensorName),
            MedicalFact(label: S.sensorActive, value: f.percent(stats.coverage, decimals: 1)),
            MedicalFact(label: S.readings, value: f.integer(stats.readings)),
        ]
    }

    /// Glucosa media, GMI, CV y desviación estándar. GMI = 3,31 + 0,02392 × media (mg/dL).
    static func metrics(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> [MedicalFact] {
        let stats = bundle.summary.stats
        let gmi = stats.mean.map { gmiPercent(meanMgdl: $0) }
        return [
            MedicalFact(label: S.meanGlucose(f.unit.symbol), value: f.glucose(stats.mean)),
            MedicalFact(label: S.gmi, value: gmi.map { "\(f.number($0, decimals: 1)) %" } ?? MedicalReportFormatter.dash),
            MedicalFact(label: S.cv, value: f.percent(stats.coefficientOfVariation, decimals: 1)),
            MedicalFact(label: S.sd(f.unit.symbol), value: f.glucose(stats.standardDeviation)),
        ]
    }

    /// Indicador de gestión de glucosa (%), sin redondear.
    static func gmiPercent(meanMgdl: Double) -> Double { 3.31 + 0.02392 * meanMgdl }

    /// Barra de tiempo en los cinco tramos del consenso y, si el rango personal es otro, su línea.
    static func rangeSection(_ bundle: ReportBundle, _ f: MedicalReportFormatter) -> ([MedicalRangeRow], String?) {
        let distribution = MedicalTimeInRange(series: bundle.series)
        let names = [S.veryLow, S.low, S.inRange, S.high, S.veryHigh]
        let texts = rangeTexts(f)
        let rows = MedicalRangeBand.allCases.map { band -> MedicalRangeRow in
            let fraction = distribution.fraction(band)
            return MedicalRangeRow(
                band: band, name: names[band.rawValue], rangeText: texts[band.rawValue], fraction: fraction,
                percentText: distribution.hasData ? f.percent(fraction, decimals: 1) : MedicalReportFormatter.dash,
                perDayText: distribution.hasData ? f.timePerDay(fraction: fraction) : MedicalReportFormatter.dash)
        }
        let configuration = bundle.configuration
        var personal: String?
        if (configuration.rangeLow, configuration.rangeHigh) != (70, 180), let share = bundle.summary.stats.timeInRange {
            personal = S.personalRange(f.glucose(Double(configuration.rangeLow)), f.glucose(Double(configuration.rangeHigh)),
                                       f.unit.symbol, f.percent(share, decimals: 1))
        }
        return (rows, personal)
    }

    /// "<54", "54–69", "70–180", "181–250", ">250" (mg/dL) o su equivalente en mmol/L.
    static func rangeTexts(_ f: MedicalReportFormatter) -> [String] {
        switch f.unit {
        case .mgdl:
            return ["<54", "54–69", "70–180", "181–250", ">250"]
        case .mmol:
            let cuts = [3.0, 3.9, 10.0, 13.9].map { f.number($0, decimals: 1) }
            let nextAbove = [3.8, 10.0, 13.9].map { f.number($0, decimals: 1) }
            let aboveTarget = f.number(10.1, decimals: 1)
            return ["<\(cuts[0])", "\(cuts[0])–\(nextAbove[0])", "\(cuts[1])–\(nextAbove[1])",
                    "\(aboveTarget)–\(nextAbove[2])", ">\(cuts[3])"]
        }
    }
}
