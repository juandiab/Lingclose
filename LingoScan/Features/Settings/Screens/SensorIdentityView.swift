import SwiftUI
import UniformTypeIdentifiers

/// Ajustes › Avanzado › Identidad del sensor: qué es, qué hay cargado (etiqueta y familias, nunca el contenido) e
/// importación de un archivo. Si ya hay una identidad, pide confirmación antes de reemplazarla.
struct SensorIdentityView: View {
    let model: IdentityImportModel?
    @State private var isPickingFile = false
    @State private var isConfirmingReplace = false

    var body: some View {
        Form {
            if let model {
                statusSection(model)
                importSection(model)
            } else {
                Section {
                    Label(String(localized: "settings.preview.unavailable", defaultValue: "No disponible en la vista previa"),
                          systemImage: "key.slash")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text(explanation)
                }
            }
        }
        .navigationTitle(String(localized: "identity.header", defaultValue: "Identidad del sensor"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task { await model?.importIdentity(from: url) }
            case .failure:
                model?.reportPickerFailure()
            }
        }
        .task { await model?.refresh() }
    }

    private var explanation: String {
        String(localized: "identity.footer", defaultValue: "Son las credenciales que permiten a Lingclose emparejarse con tu biosensor (Abbott Lingo). Llegan en un archivo .json y se guardan solo en el llavero de este iPhone; el archivo original no se modifica.")
    }

    private func statusSection(_ model: IdentityImportModel) -> some View {
        Section {
            if model.summaries.isEmpty {
                Label(String(localized: "identity.none", defaultValue: "No hay identidad cargada: el sensor no se puede emparejar."),
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.summaries) { summary in
                LabeledContent(summary.label) {
                    Text(familiesText(summary))
                }
            }
            if !model.summaries.isEmpty {
                LabeledContent(String(localized: "identity.signingKeys", defaultValue: "Claves para emparejar tu biosensor (Abbott Lingo)")) {
                    Text(model.hasLingoSigningKeys
                         ? String(localized: "identity.signingKeys.present", defaultValue: "Presentes")
                         : String(localized: "identity.signingKeys.missing", defaultValue: "Faltan: no se puede emparejar"))
                }
            }
        } header: {
            Text(String(localized: "identity.loaded", defaultValue: "Cargada en este iPhone"))
        } footer: {
            Text(explanation)
        }
    }

    private func importSection(_ model: IdentityImportModel) -> some View {
        Section {
            Button {
                if model.summaries.isEmpty { isPickingFile = true } else { isConfirmingReplace = true }
            } label: {
                if model.isImporting {
                    ProgressView()
                } else {
                    Label(String(localized: "identity.import.action", defaultValue: "Importar archivo de identidad"),
                          systemImage: "square.and.arrow.down")
                }
            }
            .disabled(model.isImporting)
            .confirmationDialog(
                String(localized: "identity.replace.title", defaultValue: "¿Reemplazar la identidad del sensor?"),
                isPresented: $isConfirmingReplace,
                titleVisibility: .visible
            ) {
                Button(String(localized: "identity.replace.confirm", defaultValue: "Elegir archivo y reemplazar"), role: .destructive) {
                    isPickingFile = true
                }
                Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
            } message: {
                Text(String(localized: "identity.replace.message", defaultValue: "Si el archivo nuevo no sirve para tu sensor, dejará de conectarse. La identidad actual solo se sustituye si el archivo es válido."))
            }
        } footer: {
            Text(String(localized: "identity.import.footer", defaultValue: "Solo hace falta una vez, antes de emparejar un sensor. Importar otro archivo reemplaza el actual."))
        }
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

#Preview {
    NavigationStack {
        SensorIdentityView(model: nil)
    }
}
