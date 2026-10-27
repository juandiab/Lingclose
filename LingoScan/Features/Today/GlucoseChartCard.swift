import SwiftUI

/// Tarjeta sólida con la curva, la lectura al arrastrar y la leyenda. Sin vidrio bajo la gráfica.
struct GlucoseChartCard: View {
    let viewModel: TodayViewModel
    @State private var selection = ChartSelection()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                SelectionReadout(viewModel: viewModel, selection: selection)
                if viewModel.points.isEmpty && viewModel.hasLoaded {
                    ContentUnavailableView(
                        String(localized: "today.chart.empty.title", defaultValue: "Sin lecturas en este período"),
                        systemImage: "chart.xyaxis.line"
                    )
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.36 }
                } else {
                    GlucoseChart(viewModel: viewModel, selection: selection)
                }
                ChartLegend(low: viewModel.referenceLow, high: viewModel.referenceHigh)
            }
        }
        // Al cambiar de día o período la selección anterior ya no significa nada.
        .onChange(of: viewModel.windowKey) { selection.date = nil }
    }
}
