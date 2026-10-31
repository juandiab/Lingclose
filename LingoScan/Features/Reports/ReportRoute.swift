/// Detalle de cada card de Reportes (también identificador de la transición de zoom), en el orden de la pantalla.
enum ReportRoute: String, Hashable, CaseIterable, Identifiable {
    case summary, hourlyProfile, dailyOverlay, weeklyComparison, meals, nights, exercise, timeOfDay

    var id: Self { self }

    var title: String {
        switch self {
        case .summary: String(localized: "reports.summary.title", defaultValue: "Resumen del período")
        case .hourlyProfile: String(localized: "reports.profile.title", defaultValue: "Perfil por hora del día")
        case .dailyOverlay: String(localized: "reports.overlay.title", defaultValue: "Días superpuestos")
        case .weeklyComparison: String(localized: "reports.weekly.title", defaultValue: "Semana a semana")
        case .meals: String(localized: "reports.meals.title", defaultValue: "Respuesta a comidas")
        case .nights: String(localized: "reports.nights.title", defaultValue: "Noche")
        case .exercise: String(localized: "reports.exercise.title", defaultValue: "Efecto del ejercicio")
        case .timeOfDay: String(localized: "reports.slots.title", defaultValue: "Patrones por franja")
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "square.grid.2x2"
        case .hourlyProfile: "clock"
        case .dailyOverlay: "square.stack.3d.down.right"
        case .weeklyComparison: "arrow.left.arrow.right"
        case .meals: "fork.knife"
        case .nights: "moon.stars"
        case .exercise: "figure.run"
        case .timeOfDay: "sun.horizon"
        }
    }

    /// El detalle solo se abre si tiene algo que mostrar.
    func hasDetail(_ content: ReportContent) -> Bool {
        let bundle = content.bundle
        return switch self {
        case .summary: bundle.summary.hasEnoughData
        case .hourlyProfile: bundle.hourlyProfile.hasEnoughData
        case .dailyOverlay: bundle.dailyOverlay.hasEnoughData
        case .weeklyComparison: bundle.weeklyComparison.hasEnoughData
        case .meals: !bundle.meals.meals.isEmpty
        case .nights: bundle.nights.nights.contains { $0.stats.hasReadings }
        case .exercise: !bundle.exercise.sessions.isEmpty
        case .timeOfDay: bundle.timeOfDay.hasEnoughData
        }
    }
}
