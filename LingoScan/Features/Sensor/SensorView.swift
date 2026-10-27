import SwiftUI

/// Pantalla Sensor: estado, calentamiento, días restantes, última conexión y Receiver ID parcial.
/// Se empuja desde el chip de Hoy (y más adelante desde Ajustes), por eso no crea su propio `NavigationStack`.
struct SensorView: View {
    @Bindable var viewModel: SensorViewModel
    @State private var now = Date.now

    var body: some View {
        Form {
            SensorStatusSection(status: viewModel.status, now: now)
            SensorActionsSection(viewModel: viewModel)
        }
        .navigationTitle(String(localized: "sensor.title", defaultValue: "Sensor"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.observe() }
        .task { await tickEveryThirtySeconds() }
        .sheet(item: $viewModel.activationSummary) { summary in
            ActivationConfirmationView(summary: summary) { confirmation in
                Task { await viewModel.confirmActivation(confirmation) }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.lastConfirmation)
    }
}

extension SensorView {
    /// Refresca `now` para que "última conexión" y los restantes sigan al reloj.
    private func tickEveryThirtySeconds() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = .now
        }
    }
}

#Preview("Conectado") {
    NavigationStack {
        SensorView(viewModel: SensorViewModel(statusSource: PreviewData()))
    }
}

#Preview("Listo para activar") {
    let model = SensorViewModel(statusSource: PreviewData(sensorState: .readyToActivate))
    model.activateAction = { _ in }
    model.readSensorAction = {}
    return NavigationStack {
        SensorView(viewModel: model)
    }
}
