import SwiftUI

/// Pantalla Hoy: valor actual, chip de estado del sensor y curva 3 h / 6 h / 24 h.
struct TodayView: View {
    @Bindable var viewModel: TodayViewModel
    let sensorViewModel: SensorViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    SensorStatusChip(state: viewModel.sensor.state)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        CurrentValueView(viewModel: viewModel, now: context.date)
                    }
                    if viewModel.failure != nil {
                        Label(
                            String(localized: "today.failure", defaultValue: "No se pudieron leer los datos guardados."),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(Tokens.Palette.error)
                    }
                    PeriodPicker(period: $viewModel.period)
                    GlucoseChartCard(viewModel: viewModel)
                    if viewModel.isSynthetic {
                        Label(
                            String(localized: "today.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real."),
                            systemImage: "testtube.2"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.bottom, Tokens.Spacing.md)
            }
            .navigationTitle(String(localized: "today.title", defaultValue: "Hoy"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TodayRoute.self) { _ in
                SensorView(viewModel: sensorViewModel)
            }
        }
        .task { await viewModel.observe() }
        .task(id: viewModel.period) { await viewModel.refresh() }
        .sensoryFeedback(.warning, trigger: viewModel.sensor.state) { _, newState in
            newState == .stale
        }
    }
}

#Preview {
    let data = PreviewData()
    return TodayView(
        viewModel: TodayViewModel(dataSource: data, sensorSource: data),
        sensorViewModel: SensorViewModel(statusSource: data)
    )
}
