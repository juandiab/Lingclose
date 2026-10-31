import SwiftUI

/// Ajustes › Conexiones › Asistente con IA: modelo elegido (o "Sin configurar") y enlace a su pantalla. El estado se
/// relee al volver de ella; la clave nunca se lee aquí, solo si existe.
struct AssistantRow: View {
    let services: MealAssistantServices
    @State private var configuredModel: String?

    var body: some View {
        NavigationLink(value: SettingsRoute.assistant) {
            LabeledContent {
                Text(configuredModel ?? String(localized: "settings.assistant.notConfigured", defaultValue: "Sin configurar"))
                    .lineLimit(2)
            } label: {
                SettingsRowTitle(title: String(localized: "llm.title", defaultValue: "Asistente con IA"), systemImage: "sparkles")
            }
        }
        // `.task` vuelve a ejecutarse cada vez que la fila reaparece (al volver de la pantalla del asistente).
        .task { await refresh() }
    }

    private func refresh() async {
        guard let provider = services.settings.selectedProvider(),
              let model = services.settings.selectedModel(for: provider),
              await services.keys.hasKey(for: provider) else {
            configuredModel = nil
            return
        }
        configuredModel = model.displayName
    }
}
