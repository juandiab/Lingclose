import SwiftUI

/// Entrada del análisis: foto y/o descripción, y el botón "Analizar". Si falta configurar el asistente,
/// lo dice y enlaza a Ajustes.
struct MealInputSection: View {
    @Bindable var model: MealAnalysisViewModel
    let services: MealAssistantServices

    var body: some View {
        switch model.readiness {
        case .checking:
            Section { ProgressView() }
        case .notConfigured:
            Section {
                Label(
                    String(localized: "meal.notConfigured", defaultValue: "Falta elegir un proveedor con clave y un modelo."),
                    systemImage: "gearshape")
                NavigationLink(String(localized: "meal.openSettings", defaultValue: "Abrir ajustes del asistente")) {
                    LLMSettingsView(services: services)
                }
            }
        case .ready(let llm):
            readyContent(llm)
        }
    }

    @ViewBuilder
    private func readyContent(_ llm: LLMModel) -> some View {
        Section {
            MealPhotoPicker(photoJPEG: model.photoJPEG) { model.setPhoto($0) }
            TextField(
                String(localized: "meal.description", defaultValue: "Describe el plato o snack, o escribe «etiqueta»"),
                text: $model.descriptionText,
                axis: .vertical)
                .lineLimit(1...4)
        } footer: {
            Text(String(localized: "meal.privacy", defaultValue: "Solo se envían la foto reducida y tu descripción. Nada de glucosa, Salud ni entrenamientos; la foto no se guarda."))
        }
        if model.photoBlockedByModel {
            Section {
                Label(
                    String(localized: "meal.noVision", defaultValue: "Este modelo no analiza fotos. Puedes analizar solo la descripción."),
                    systemImage: "photo.badge.exclamationmark")
                Button(String(localized: "meal.dropPhoto", defaultValue: "Quitar la foto y usar solo la descripción")) {
                    model.discardPhoto()
                }
            }
        }
        Section {
            Button {
                model.startAnalysis()
            } label: {
                Text(String(localized: "meal.analyze", defaultValue: "Analizar"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!model.canAnalyze)
            .listRowBackground(Color.clear)
        } footer: {
            let name = llm.displayName
            Text(String(localized: "meal.model", defaultValue: "Modelo: \(name)"))
        }
    }
}
