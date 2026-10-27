import SwiftUI

/// Acciones del sensor. La lectura (solo NFC) y la activación son botones y secciones distintas.
struct SensorActionsSection: View {
    @Bindable var viewModel: SensorViewModel

    var body: some View {
        Section {
            Button(action: readSensor) {
                if viewModel.isReading {
                    ProgressView()
                } else {
                    Label(
                        String(localized: "sensor.action.read", defaultValue: "Leer sensor (solo NFC)"),
                        systemImage: "wave.3.right"
                    )
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.canReadSensor)
        } footer: {
            Text(String(localized: "sensor.action.read.footer", defaultValue: "Solo lectura: identifica el sensor y no lo activa."))
        }

        Section {
            Button(action: beginActivation) {
                if viewModel.isPreparing {
                    ProgressView()
                } else {
                    Label(
                        String(localized: "sensor.action.activate", defaultValue: "Activar sensor"),
                        systemImage: "bolt.horizontal.circle"
                    )
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.canActivate)
        } footer: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                if let blocker = viewModel.activationBlocker {
                    Text(blocker.explanation)
                }
                Text(String(localized: "sensor.action.activate.footer", defaultValue: "Abre una pantalla aparte con el resumen de lo que se enviará. Un sensor se activa una sola vez."))
            }
        }
    }

    private func readSensor() {
        Task { await viewModel.readSensor() }
    }

    private func beginActivation() {
        Task { await viewModel.beginActivation() }
    }
}
