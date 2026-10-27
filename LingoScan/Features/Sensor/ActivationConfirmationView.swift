import SwiftUI

/// Pantalla aparte de activación: muestra lo que se enviará y exige un toggle explícito.
/// No envía nada: al confirmar entrega un `ActivationConfirmation` por closure.
struct ActivationConfirmationView: View {
    let summary: ActivationSummary
    let onConfirm: (ActivationConfirmation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var understandsIrreversible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(String(localized: "activation.family", defaultValue: "Familia")) {
                        Text(summary.family.displayName)
                    }
                    LabeledContent {
                        Text(summary.productType, format: .number.grouping(.never))
                            .monospacedDigit()
                    } label: {
                        Text(verbatim: "productType")
                    }
                    LabeledContent {
                        Text(summary.securityVersion, format: .number.grouping(.never))
                            .monospacedDigit()
                    } label: {
                        Text(verbatim: "securityVersion")
                    }
                    LabeledContent(String(localized: "activation.serial", defaultValue: "Serial")) {
                        Text(summary.serialRedacted)
                            .monospaced()
                    }
                    LabeledContent(String(localized: "activation.warmup", defaultValue: "Calentamiento")) {
                        RemainingDurationText(duration: .seconds(summary.warmupMinutes * 60))
                    }
                    LabeledContent(String(localized: "activation.wear", defaultValue: "Duración")) {
                        RemainingDurationText(duration: .seconds(summary.wearMinutes * 60))
                    }
                    LabeledContent {
                        Text(summary.receiverIDText)
                            .monospaced()
                            .textSelection(.enabled)
                    } label: {
                        Text(verbatim: "Receiver ID")
                    }
                    LabeledContent(String(localized: "activation.time", defaultValue: "Hora")) {
                        Text(summary.preparedAt, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                } header: {
                    Text(String(localized: "activation.summary.header", defaultValue: "Se enviará al sensor"))
                } footer: {
                    Text(String(localized: "activation.summary.footer", defaultValue: "Anota el Receiver ID completo: ya está guardado en este iPhone. Activar es irreversible: un sensor se activa una sola vez y no se puede deshacer."))
                }

                Section {
                    Toggle(
                        String(localized: "activation.understand", defaultValue: "Entiendo que es irreversible"),
                        isOn: $understandsIrreversible
                    )
                }

                Section {
                    Button(action: confirm) {
                        Text(String(localized: "activation.confirm", defaultValue: "Activar sensor"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!understandsIrreversible)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle(String(localized: "activation.title", defaultValue: "Activar sensor"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "activation.cancel", defaultValue: "Cancelar"), role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func confirm() {
        onConfirm(ActivationConfirmation(confirmationID: UUID(), confirmedAt: .now))
    }
}

#Preview {
    ActivationConfirmationView(
        summary: ActivationSummary(
            family: .lingo,
            productType: 9,
            securityVersion: 3,
            serialRedacted: "SYN…01",
            warmupMinutes: 60,
            wearMinutes: 20_160,
            receiverID: 0x1234_5678,
            preparedAt: .now
        ),
        onConfirm: { _ in }
    )
}
