import SwiftUI

/// Bloque de la curva: chips de período, una línea con el período visible o la lectura del cursor (y el botón
/// de leyenda), y la gráfica sobre el fondo de la pantalla. Sin tarjeta ni vidrio bajo la gráfica; el vidrio
/// queda en los chips y en el botón "Ahora" (`ChartNowButton`), que aparece al desplazarse al pasado.
struct GlucoseChartCard: View {
    let viewModel: TodayViewModel
    let onSelectPeriod: (TodayPeriod) -> Void
    @State private var selection = ChartSelection()

    /// Alto de la gráfica respecto al contenedor desplazable (≈ 38 % del alto de la pantalla en un iPhone; Juampa pidió un 10 % menos para ver estadísticas y Registro sin desplazar).
    static let heightFraction = 0.56

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            PeriodPicker(viewModel: viewModel, onSelect: onSelectPeriod)
            HStack(alignment: .center, spacing: Tokens.Spacing.xs) {
                SelectionReadout(viewModel: viewModel, selection: selection)
                ChartLegendButton(low: viewModel.referenceLow, high: viewModel.referenceHigh)
            }
            if viewModel.points.isEmpty && viewModel.hasLoaded {
                ContentUnavailableView(
                    String(localized: "today.chart.empty.title", defaultValue: "Sin lecturas en este período"),
                    systemImage: "chart.xyaxis.line"
                )
                .containerRelativeFrame(.vertical) { height, _ in height * Self.heightFraction }
                .overlay(alignment: .topTrailing) { ChartNowButton(viewModel: viewModel) }
            } else {
                GlucoseChart(viewModel: viewModel, selection: selection)
                    .overlay(alignment: .topTrailing) { ChartNowButton(viewModel: viewModel) }
            }
        }
        // Al cambiar de día la selección anterior ya no significa nada.
        .onChange(of: viewModel.shownDay) { selection.date = nil }
    }
}
