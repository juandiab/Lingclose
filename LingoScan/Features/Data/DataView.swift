import SwiftUI
import UniformTypeIdentifiers

/// Datos: Apple Salud, archivo portable, recuperación y errores recientes.
struct DataView: View {
    let viewModel: DataViewModel

    private enum Picker {
        case folder
        case package
    }

    @State private var picker: Picker?
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            Form {
                HealthSection(viewModel: viewModel)
                ArchiveSection(
                    viewModel: viewModel,
                    onChooseFolder: { open(.folder) },
                    onImport: { open(.package) })
                Section {
                    NavigationLink {
                        RecoveryView()
                    } label: {
                        Label(String(localized: "data.recovery", defaultValue: "Archivo de recuperación"), systemImage: "key.viewfinder")
                    }
                } footer: {
                    Text(String(localized: "data.recovery.footer", defaultValue: "Copia cifrada con frase para recuperar el sensor activo en otra instalación."))
                }
                RecentErrorsSection(viewModel: viewModel)
            }
            .navigationTitle(String(localized: "data.title", defaultValue: "Datos"))
            .appBackground()
            .task { await viewModel.refresh() }
            .refreshable { await viewModel.refresh() }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: allowedTypes) { result in
                handle(result)
            }
        }
    }

    private var allowedTypes: [UTType] {
        [.folder, UTType(filenameExtension: "lingoscan", conformingTo: .directory)].compactMap { $0 }
    }

    private func open(_ kind: Picker) {
        picker = kind
        isPicking = true
    }

    private func handle(_ result: Result<URL, any Error>) {
        defer { picker = nil }
        guard case .success(let url) = result, let picker else { return }
        switch picker {
        case .folder: Task { await viewModel.chooseFolder(url) }
        case .package: Task { await viewModel.importPackages(from: url) }
        }
    }
}
