import LingoCore
import SwiftUI

/// Hoja "Analizar con IA": entrada (foto y/o descripción), análisis cancelable y propuesta editable.
/// Se presenta como raíz de una hoja (lleva su propio `NavigationStack`).
struct MealAnalysisView: View {
    @Bindable var model: MealAnalysisViewModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.mealAssistant) private var services

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .input:
                    MealInputSection(model: model, services: services)
                case .analyzing:
                    analyzingSection
                case .failed(let message):
                    failedSection(message)
                case .proposal:
                    MealProposalView(model: model)
                }
            }
            .navigationTitle(model.phase == .proposal
                ? String(localized: "meal.title.proposal", defaultValue: "Propuesta")
                : String(localized: "meal.title.analyze", defaultValue: "Analizar con IA"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancelar")) {
                        model.cancelAnalysis()
                        dismiss()
                    }
                }
                if model.phase == .proposal {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.save", defaultValue: "Guardar"), action: save)
                        .disabled(!model.canSave)
                    }
                }
            }
            .onAppear { Task { await model.prepare() } }
            .sensoryFeedback(.success, trigger: model.didSave)
            .animation(.smooth, value: model.phase)
        }
        .interactiveDismissDisabled(model.phase == .analyzing || model.isSaving)
        .presentationDetents([.large])
    }

    private func save() {
        Task {
            guard await model.save() else { return }
            onSaved()
            dismiss()
        }
    }

    private var analyzingSection: some View {
        Section {
            HStack(spacing: Tokens.Spacing.sm) {
                ProgressView()
                Text(String(localized: "meal.analyzing", defaultValue: "Analizando…"))
            }
            Button(String(localized: "meal.cancelAnalysis", defaultValue: "Cancelar análisis"), role: .cancel) {
                model.cancelAnalysis()
            }
        }
    }

    private func failedSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Tokens.Palette.error)
            Button(String(localized: "meal.retry", defaultValue: "Reintentar")) {
                model.startAnalysis()
            }
            .disabled(!model.canAnalyze)
            Button(String(localized: "meal.back", defaultValue: "Volver")) {
                model.backToInput()
            }
        } footer: {
            Text(String(localized: "meal.retry.footer", defaultValue: "Cada intento es una llamada nueva al proveedor y puede costar. No se repite solo."))
        }
    }
}
