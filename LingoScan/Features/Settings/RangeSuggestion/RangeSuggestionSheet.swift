import SwiftUI

/// Hoja de revisión de "Sugerir rango": rango propuesto, origen, explicación, cada dato con su fuente y el
/// aviso de no uso médico. El usuario acepta ("Usar rango") o descarta; nada cambia hasta entonces. Mientras
/// calcula no se puede cerrar deslizando (la llamada al asistente podría costar) y "Descartar" la cancela.
struct RangeSuggestionSheet: View {
    let currentLow: Int
    let currentHigh: Int
    let onAccept: (_ low: Int, _ high: Int) -> Void

    @State private var model: RangeSuggestionViewModel
    @Environment(\.dismiss) private var dismiss

    init(suggester: any RangeSuggesting, currentLow: Int, currentHigh: Int, onAccept: @escaping (_ low: Int, _ high: Int) -> Void) {
        self.currentLow = currentLow
        self.currentHigh = currentHigh
        self.onAccept = onAccept
        _model = State(initialValue: RangeSuggestionViewModel(suggester: suggester))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .loading:
                    loadingSection
                case .failed(let message):
                    failedSection(message)
                case .ready(let suggestion):
                    RangeSuggestionContent(
                        suggestion: suggestion, currentLow: currentLow, currentHigh: currentHigh,
                        applied: model.applied, isAdjusted: model.isAdjustedForSettings)
                }
                disclaimerSection
            }
            .navigationTitle(String(localized: "range.suggest.title", defaultValue: "Rango sugerido"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "range.suggest.discard", defaultValue: "Descartar"), action: discard)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "range.suggest.accept", defaultValue: "Usar rango"), action: accept)
                        .disabled(!model.canAccept)
                }
            }
            .task { await model.load() }
            .onDisappear(perform: model.cancel)
            .animation(.smooth, value: model.phase)
        }
        .interactiveDismissDisabled(model.phase == .loading)
        .presentationDetents([.large])
    }

    private func accept() {
        guard let applied = model.applied else { return }
        onAccept(applied.low, applied.high)
        dismiss()
    }

    private func discard() {
        model.cancel()
        dismiss()
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: Tokens.Spacing.sm) {
                ProgressView()
                Text(String(localized: "range.suggest.loading", defaultValue: "Calculando con tus lecturas…"))
            }
        } footer: {
            Text(String(localized: "range.suggest.loading.footer", defaultValue: "Se leen tus lecturas de los últimos 14 días y, si lo permites, edad, sexo, peso y altura de Salud. Si hay un asistente configurado recibe solo cifras agregadas: nunca lecturas sueltas."))
        }
    }

    private func failedSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Tokens.Palette.error)
            Button(String(localized: "common.close", defaultValue: "Cerrar")) { dismiss() }
        }
    }

    private var disclaimerSection: some View {
        Section {
            Label {
                Text(String(localized: "range.suggest.disclaimer", defaultValue: "Esta sugerencia no es consejo médico ni sustituye a un profesional de la salud. Las líneas solo ayudan a leer la curva; LingoScan no es un dispositivo médico. Nada cambia hasta que pulses \"Usar rango\"."))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Lista") {
    RangeSuggestionSheet(suggester: PreviewRangeSuggester(), currentLow: 70, currentHigh: 140) { _, _ in }
}

#Preview("Cobertura insuficiente") {
    RangeSuggestionSheet(
        suggester: PreviewRangeSuggester(result: .failure(.insufficientCoverage(hours: 5.2, required: 24))),
        currentLow: 70, currentHigh: 140) { _, _ in }
}
