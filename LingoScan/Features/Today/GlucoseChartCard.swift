import SwiftUI

/// Tarjeta sólida con la curva, la lectura al tocar y la leyenda. Sin vidrio bajo la gráfica.
struct GlucoseChartCard: View {
    let viewModel: TodayViewModel
    @State private var selectedDate: Date?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                SelectionReadout(point: selectedDate.flatMap(viewModel.nearestPoint(to:)), period: viewModel.period)
                if viewModel.points.isEmpty && viewModel.hasLoaded {
                    ContentUnavailableView(
                        String(localized: "today.chart.empty.title", defaultValue: "Sin lecturas en este período"),
                        systemImage: "chart.xyaxis.line"
                    )
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.32 }
                } else {
                    GlucoseChart(viewModel: viewModel, selectedDate: $selectedDate)
                }
                ChartLegend()
            }
        }
    }
}
