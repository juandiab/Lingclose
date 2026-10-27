import LingoCore
import SwiftUI

/// Propuesta editable: tipo detectado, nombre, base, cuatro cifras, slider de porciones, supuestos y
/// confianza. También sirve para reabrir una comida guardada.
struct MealProposalView: View {
    @Bindable var model: MealAnalysisViewModel

    var body: some View {
        if model.kind == .notFood {
            notFoodSection
        } else {
            if let notice = model.externalChangeNotice {
                Section {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Tokens.Palette.outOfRange)
                }
            }
            detailsSection
            figuresSection
            portionsSection
            notesSection
            if let failure = model.saveFailure {
                Section {
                    Label(failureText(failure), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Tokens.Palette.error)
                }
            }
        }
    }

    private var notFoodSection: some View {
        Section {
            Label(
                String(localized: "meal.kind.notFood", defaultValue: "No parece comida"),
                systemImage: "questionmark.circle")
            Text(String(localized: "meal.notFood.help", defaultValue: "No hay nada que registrar con esta foto o descripción. Prueba con otra."))
                .foregroundStyle(.secondary)
            Button(String(localized: "meal.back", defaultValue: "Volver")) { model.backToInput() }
        }
    }

    private var detailsSection: some View {
        Section {
            LabeledContent(String(localized: "meal.kind", defaultValue: "Detectado")) {
                Text(kindTitle)
            }
            TextField(String(localized: "meal.name", defaultValue: "Nombre"), text: $model.name)
            if let summary = model.basisSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DatePicker(String(localized: "diary.editor.time", defaultValue: "Hora"), selection: $model.at)
        }
    }

    private var figuresSection: some View {
        Section {
            ForEach(NutrientField.allCases, id: \.self) { field in
                NutrientFieldRow(
                    field: field,
                    text: $model[text: field],
                    isManual: model.isManual(field),
                    isInvalid: model.isInvalid(field),
                    onReset: { model.reset(field) },
                    onCommit: { model.commitEditing(field) })
            }
        } header: {
            Text(String(localized: "meal.figures", defaultValue: "Nutrientes"))
        }
    }

    private var portionsSection: some View {
        Section {
            if model.hasFigures {
                PortionSlider(
                    multiplier: $model.sliderValue,
                    multiplierText: model.multiplierText)
            } else {
                Text(String(localized: "meal.noFigures", defaultValue: "No hay cifras que ajustar: el modelo no pudo estimar nutrientes para esto"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if model.assumptions != nil || model.confidenceText != nil || model.unreadableText != nil {
            Section {
                if let assumptions = model.assumptions {
                    Text(assumptions)
                }
                if let confidence = model.confidenceText {
                    Text(confidence).monospacedDigit()
                }
                if let unreadable = model.unreadableText {
                    Text(unreadable)
                }
            } header: {
                Text(String(localized: "meal.notes", defaultValue: "Supuestos"))
            }
        }
    }

    private var kindTitle: String {
        switch model.kind {
        case .food: String(localized: "meal.kind.food", defaultValue: "Comida")
        case .nutritionLabel: String(localized: "meal.kind.label", defaultValue: "Etiqueta nutricional")
        case .notFood: String(localized: "meal.kind.notFood", defaultValue: "No parece comida")
        }
    }

    private func failureText(_ failure: MealAnalysisViewModel.SaveFailure) -> String {
        switch failure {
        case .failed: String(localized: "diary.failure.save", defaultValue: "No se pudo guardar. Inténtalo de nuevo.")
        case .conflict: String(localized: "meal.failure.conflict", defaultValue: "Este registro tiene una edición más nueva; no se sobrescribió.")
        }
    }
}
