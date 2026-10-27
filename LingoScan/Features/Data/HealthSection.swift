import SwiftUI

/// Tarjeta Health: permiso, huecos pendientes, último intento y "Rellenar huecos" (opt-in con confirmación).
struct HealthSection: View {
    @Bindable var viewModel: DataViewModel

    var body: some View {
        Section {
            HStack {
                Text(String(localized: "data.health.permission", defaultValue: "Permiso"))
                Spacer(minLength: Tokens.Spacing.xs)
                if viewModel.health.isAuthorized {
                    Label(String(localized: "data.health.authorized", defaultValue: "Concedido"), systemImage: "checkmark.circle")
                        .foregroundStyle(Tokens.Palette.inRange)
                } else {
                    Label(String(localized: "data.health.notAuthorized", defaultValue: "No concedido"), systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if !viewModel.health.isAuthorized {
                Button(String(localized: "data.health.request", defaultValue: "Pedir permiso de Apple Salud"), systemImage: "heart.text.square") {
                    Task { await viewModel.requestHealthAuthorization() }
                }
                .disabled(viewModel.isHealthBusy)
            }
            LabeledContent(String(localized: "data.health.pending", defaultValue: "Huecos pendientes")) {
                Text(viewModel.health.pendingCount, format: .number)
                    .monospacedDigit()
            }
            LabeledContent(String(localized: "data.health.lastAttempt", defaultValue: "Último intento")) {
                if let date = viewModel.health.lastAttempt {
                    Text(date, format: .dateTime.day().month().hour().minute())
                } else {
                    Text(String(localized: "data.health.never", defaultValue: "Ninguno"))
                }
            }
            if viewModel.health.isPaused {
                Label(
                    String(localized: "data.health.paused", defaultValue: "En pausa: no se escribe en Apple Salud."),
                    systemImage: "pause.circle"
                )
                .foregroundStyle(.secondary)
            }
            if let error = viewModel.health.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.error)
            }
            Button(String(localized: "data.health.fill", defaultValue: "Rellenar huecos…"), systemImage: "arrow.down.heart") {
                viewModel.isConfirmingFillGaps = true
            }
            .disabled(!viewModel.canFillGaps)
            if let fill = viewModel.lastFill {
                Text(fillSummary(fill))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "data.health.header", defaultValue: "Apple Salud"))
        } footer: {
            Text(String(localized: "data.health.footer", defaultValue: "Solo se escriben lecturas reales y elegibles; los datos de ejemplo nunca se envían."))
        }
        .confirmationDialog(
            String(localized: "data.health.fill.title", defaultValue: "¿Rellenar huecos en Apple Salud?"),
            isPresented: $viewModel.isConfirmingFillGaps,
            titleVisibility: .visible
        ) {
            Button(String(localized: "data.health.fill.confirm", defaultValue: "Rellenar huecos")) {
                Task { await viewModel.fillGaps() }
            }
        } message: {
            Text(String(localized: "data.health.fill.message", defaultValue: "Escribe todas las lecturas y comidas pendientes, también las anteriores a un traspaso de rol. Es opcional y solo se hace cuando lo pides."))
        }
    }

    private func fillSummary(_ fill: HealthDrainSummary) -> String {
        if fill.paused {
            return String(localized: "data.health.fill.paused", defaultValue: "No se escribió nada: la app está en pausa.")
        }
        if fill.stoppedByError {
            return String(localized: "data.health.fill.error", defaultValue: "Se detuvo por un error; los pendientes siguen intactos.")
        }
        return String(localized: "data.health.fill.result", defaultValue: "Escritas \(fill.written), reconciliadas \(fill.reconciled), fallidas \(fill.failed).")
    }
}
