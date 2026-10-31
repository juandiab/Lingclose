import LingoCore

/// Reporte calculado más lo que las gráficas necesitan ya preparado (fuera del hilo principal), para que los `body`
/// no recorran series largas.
struct ReportContent: Sendable {
    /// Ranuras del perfil y de los días superpuestos en la card (15 min); el detalle usa 5 min hasta 14 días.
    static let compactSlotMinutes = 15
    static let detailedMaxDays = 14
    /// Duración de la mini-curva de cada comida.
    static let mealCurveMinutes = 180

    let preset: ReportPeriod.Preset
    let bundle: ReportBundle
    let profile: [HourlyProfilePoint]
    let overlayCompact: [OverlayPoint]
    let overlayDetailed: [OverlayPoint]
    /// Mini-curva por comida (clave: instante de la comida), desde la serie remuestreada del período.
    let mealCurves: [UTCInstant: [MealSparkPoint]]

    init(preset: ReportPeriod.Preset, bundle: ReportBundle) {
        self.preset = preset
        self.bundle = bundle
        profile = HourlyProfilePoint.points(from: bundle.hourlyProfile)
        let days = bundle.dailyOverlay.days
        overlayCompact = OverlayPoint.points(from: days, slotMinutes: Self.compactSlotMinutes)
        overlayDetailed = days.count <= Self.detailedMaxDays
            ? OverlayPoint.points(from: days, slotMinutes: DailyOverlayReport.slotMinutes)
            : overlayCompact
        var curves: [UTCInstant: [MealSparkPoint]] = [:]
        for meal in bundle.meals.meals {
            curves[meal.at] = MealSparkPoint.curve(series: bundle.series, from: meal.at, minutes: Self.mealCurveMinutes)
        }
        mealCurves = curves
    }

    var hasData: Bool { bundle.hasData }
    var configuration: ReportConfiguration { bundle.configuration }
}
