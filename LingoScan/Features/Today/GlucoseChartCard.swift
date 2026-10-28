import SwiftUI

/// Tarjeta sólida con la curva, la lectura del cursor y la leyenda. Sin vidrio bajo la gráfica; el único
/// vidrio es el botón "Ahora" (`ChartNowButton`), que aparece al desplazarse al pasado.
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
                    .overlay(alignment: .topTrailing) { ChartNowButton(viewModel: viewModel) }
                } else {
                    GlucoseChart(viewModel: viewModel, selection: selection)
                        .overlay(alignment: .topTrailing) { ChartNowButton(viewModel: viewModel) }
                }
                ChartLegend(low: viewModel.referenceLow, high: viewModel.referenceHigh)
            }
        }
        // Al cambiar de día la selección anterior ya no significa nada.
        .onChange(of: viewModel.shownDay) { selection.date = nil }
    }
}
