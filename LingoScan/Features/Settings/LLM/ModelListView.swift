import SwiftUI

/// Lista de modelos del catálogo (ya filtrada por la búsqueda). Tocar uno lo elige.
struct ModelListView: View {
    let models: [LLMModel]
    let onChoose: (LLMModel) -> Void

    var body: some View {
        if models.isEmpty {
            Text(String(localized: "llm.models.none", defaultValue: "Ningún modelo coincide con la búsqueda."))
                .foregroundStyle(.secondary)
        } else {
            ForEach(models) { model in
                Button {
                    onChoose(model)
                } label: {
                    ModelRow(model: model)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
