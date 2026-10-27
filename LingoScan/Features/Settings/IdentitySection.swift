import SwiftUI
import UniformTypeIdentifiers

/// Fila "Importar identidad de app" y lo cargado (etiqueta y familias, nunca el contenido).
struct IdentitySection: View {
    let model: IdentityImportModel
    @State private var isPickingFile = false

    var body: some View {
        Section {
            Button(action: pickFile) {
                if model.isImporting {
                    ProgressView()
                } else {
                    Label(
                        String(localized: "identity.import.action", defaultValue: "Importar identidad de app"),
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
            .disabled(model.isImporting)
            if model.summaries.isEmpty {
                Text(String(localized: "identity.none", defaultValue: "No hay identidad cargada."))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.summaries) { summary in
                LabeledContent(summary.label) {
                    Text(familiesText(summary))
                }
            }
            if !model.summaries.isEmpty {
                LabeledContent(String(localized: "identity.signingKeys", defaultValue: "Claves de firma Lingo")) {
                    Text(model.hasLingoSigningKeys
                         ? String(localized: "identity.signingKeys.present", defaultValue: "Presentes")
                         : String(localized: "identity.signingKeys.missing", defaultValue: "Faltan"))
                }
            }
        } header: {
            Text(String(localized: "identity.header", defaultValue: "Identidad de app"))
        } footer: {
            Text(String(localized: "identity.footer", defaultValue: "Archivo JSON. Se valida y se guarda solo en el llavero de este iPhone; el archivo original no se modifica."))
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task { await model.importIdentity(from: url) }
            case .failure:
                model.reportPickerFailure()
            }
        }
        .task { await model.refresh() }
    }

    private func pickFile() {
        isPickingFile = true
    }

    private func familiesText(_ summary: IdentitySummary) -> String {
        guard !summary.families.isEmpty else {
            return String(localized: "identity.families.none", defaultValue: "Ninguna familia")
        }
        return summary.families.map { family in
            switch family {
            case "lingo": String(localized: "sensor.family.lingo", defaultValue: "Abbott Lingo")
            case "libre3": String(localized: "sensor.family.libre3", defaultValue: "FreeStyle Libre 3")
            default: family
            }
        }
        .formatted(.list(type: .and))
    }
}
