import LingoCore

/// Métricas de la comparación semana a semana, con su valor, su cambio y si el cambio es mejora.
/// En rango: más es mejor. SD y CV: menos es mejor. Media: mejor si se acerca al centro del rango de referencia.
/// Comidas y minutos de ejercicio: informativos (sin valoración).
enum WeeklyMetric: CaseIterable, Identifiable {
    case timeInRange, mean, standardDeviation, coefficientOfVariation, meals, exerciseMinutes

    var id: Self { self }

    /// Las cuatro de glucosa (card); el detalle añade comidas y ejercicio.
    static let glucose: [WeeklyMetric] = [.timeInRange, .mean, .standardDeviation, .coefficientOfVariation]

    var title: String {
        switch self {
        case .timeInRange: String(localized: "reports.stat.tir", defaultValue: "En rango")
        case .mean: String(localized: "reports.stat.mean", defaultValue: "Media")
        case .standardDeviation: String(localized: "reports.stat.sd", defaultValue: "SD")
        case .coefficientOfVariation: String(localized: "reports.stat.cv", defaultValue: "CV")
        case .meals: String(localized: "reports.weekly.meals", defaultValue: "Comidas anotadas")
        case .exerciseMinutes: String(localized: "reports.weekly.exercise", defaultValue: "Minutos de ejercicio")
        }
    }

    func value(_ week: WeeklyComparisonReport.Week) -> String {
        let stats = week.stats
        return switch self {
        case .timeInRange: ReportFormat.percent(stats.timeInRange) ?? "--"
        case .mean: ReportFormat.mgdl(stats.mean) ?? "--"
        case .standardDeviation: ReportFormat.mgdl(stats.standardDeviation) ?? "--"
        case .coefficientOfVariation: ReportFormat.percent(stats.coefficientOfVariation) ?? "--"
        case .meals: "\(week.meals)"
        case .exerciseMinutes: "\(week.exerciseMinutes)"
        }
    }

    func delta(
        current: WeeklyComparisonReport.Week,
        previous: WeeklyComparisonReport.Week,
        deltas: WeeklyComparisonReport.Deltas,
        configuration: ReportConfiguration
    ) -> ReportDelta? {
        switch self {
        case .timeInRange:
            guard let value = deltas.timeInRange else { return nil }
            let points = value * 100
            let direction = ReportDelta.direction(points, threshold: 1)
            return ReportDelta(
                text: String(localized: "reports.delta.points", defaultValue: "\(ReportFormat.signed(points)) p. p."),
                direction: direction,
                judgment: direction == .flat ? .neutral : (direction == .up ? .better : .worse))
        case .mean:
            guard let value = deltas.mean, let now = current.stats.mean, let before = previous.stats.mean else { return nil }
            let center = Double(configuration.rangeLow + configuration.rangeHigh) / 2
            let closer = abs(now - center) - abs(before - center)
            let direction = ReportDelta.direction(value, threshold: 1)
            let judgment: ReportDelta.Judgment = direction == .flat || abs(closer) < 1 ? .neutral : (closer < 0 ? .better : .worse)
            return ReportDelta(text: ReportFormat.signed(value), direction: direction, judgment: judgment)
        case .standardDeviation:
            guard let value = deltas.standardDeviation else { return nil }
            return Self.lowerIsBetter(text: ReportFormat.signed(value), value: value, threshold: 1)
        case .coefficientOfVariation:
            guard let value = deltas.coefficientOfVariation else { return nil }
            let points = value * 100
            return Self.lowerIsBetter(
                text: String(localized: "reports.delta.points", defaultValue: "\(ReportFormat.signed(points)) p. p."),
                value: points, threshold: 1)
        case .meals:
            let value = Double(deltas.meals)
            return ReportDelta(text: ReportFormat.signed(value), direction: ReportDelta.direction(value, threshold: 1), judgment: .neutral)
        case .exerciseMinutes:
            let value = Double(deltas.exerciseMinutes)
            return ReportDelta(text: ReportFormat.signed(value), direction: ReportDelta.direction(value, threshold: 1), judgment: .neutral)
        }
    }

    private static func lowerIsBetter(text: String, value: Double, threshold: Double) -> ReportDelta {
        let direction = ReportDelta.direction(value, threshold: threshold)
        return ReportDelta(
            text: text, direction: direction,
            judgment: direction == .flat ? .neutral : (direction == .down ? .better : .worse))
    }
}
