import SwiftUI

/// Pantalla de detalle de un reporte, con el fondo de la app y zoom desde su card.
struct ReportDetailView: View {
    let route: ReportRoute
    let content: ReportContent
    let namespace: Namespace.ID

    var body: some View {
        Group {
            switch route {
            case .summary: SummaryDetailView(content: content)
            case .hourlyProfile: HourlyProfileDetailView(content: content)
            case .dailyOverlay: DailyOverlayDetailView(content: content)
            case .weeklyComparison: WeeklyComparisonDetailView(content: content)
            case .meals: MealsDetailView(content: content)
            case .nights: NightsDetailView(content: content)
            case .exercise: ExerciseDetailView(content: content)
            case .timeOfDay: TimeOfDayDetailView(content: content)
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .modifier(ReportZoomTransitionModifier(route: route, namespace: namespace))
    }
}
