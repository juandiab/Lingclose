import SwiftUI

/// Ajustes → Asistente de comidas. Muestra solo lo que corresponde al paso de `LLMSettingsViewModel`.
struct LLMSettingsView: View {
    @State private var viewModel: LLMSettingsViewModel

    init(services: MealAssistantServices) {
        _viewModel = State(initialValue: LLMSettingsViewModel(
            keys: services.keys, settings: services.settings, makeProvider: services.makeProvider))
    }

    var body: some View {
        Form {
            providerSection
            switch viewModel.step {
            case .sinClave:
                keySection
            case .comprobando:
                Section {
                    HStack {
                        ProgressView()
                        Text(String(localized: "llm.checking", defaultValue: "Comprobando la clave…"))
                    }
                }
            case .catalogo:
                catalogSections
            case .elegido:
                chosenSections
            }
            Section {
            } footer: {
                Text(String(localized: "llm.privacy", defaultValue: "La clave se guarda solo en el llavero de este iPhone. Al analizar, solo se envían la foto reducida y tu descripción."))
            }
        }
        .navigationTitle(String(localized: "llm.title", defaultValue: "Asistente de comidas"))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(CatalogSearch(isEnabled: viewModel.step == .catalogo, text: $viewModel.searchText))
        .task { await viewModel.load() }
    }

    private var providerSection: some View {
        Section {
            Picker(
                String(localized: "llm.provider", defaultValue: "Proveedor"),
                selection: $viewModel.providerChoice
            ) {
                ForEach(LLMProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .disabled(viewModel.step == .comprobando)
        }
    }

    // MARK: 1. Sin clave

    private var keySection: some View {
        Section {
            if viewModel.needsModelChoice {
                Label(
                    String(localized: "llm.keySavedNoModel", defaultValue: "Clave guardada ••••; falta elegir modelo"),
                    systemImage: "key")
                Button(String(localized: "llm.checkAndList", defaultValue: "Comprobar y listar")) {
                    Task { await viewModel.checkSavedKey() }
                }
            }
            SecureField(
                String(localized: "llm.key.field", defaultValue: "Clave de API"),
                text: $viewModel.keyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "llm.saveAndCheck", defaultValue: "Guardar y comprobar")) {
                Task { await viewModel.saveAndCheck() }
            }
            .disabled(!viewModel.canSaveKey)
            if viewModel.canCancelKeyChange {
                Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                    viewModel.cancelKeyChange()
                }
            }
            messageView
        }
    }

    // MARK: 3. Catálogo

    private var catalogSections: some View {
        Group {
            Section {
                messageView
                Button(String(localized: "llm.refresh", defaultValue: "Actualizar catálogo")) {
                    Task { await viewModel.refreshCatalog() }
                }
            }
            Section {
                ModelListView(models: viewModel.filteredModels) { viewModel.choose($0) }
            } header: {
                Text(String(localized: "llm.pick", defaultValue: "Elige un modelo"))
            }
        }
    }

    // MARK: 4. Elegido

    private var chosenSections: some View {
        Group {
            Section {
                Label(String(localized: "llm.keySaved", defaultValue: "Clave guardada ••••"), systemImage: "key")
                if let model = viewModel.selectedModel {
                    ModelRow(model: model)
                }
                messageView
            }
            Section {
                Button(String(localized: "llm.changeModel", defaultValue: "Cambiar modelo")) {
                    Task { await viewModel.changeModel() }
                }
                Button(String(localized: "llm.changeKey", defaultValue: "Cambiar clave")) {
                    viewModel.changeKey()
                }
                Button(String(localized: "llm.forgetKey", defaultValue: "Olvidar clave"), role: .destructive) {
                    Task { await viewModel.forgetKey() }
                }
            }
        }
    }

    @ViewBuilder
    private var messageView: some View {
        switch viewModel.message {
        case .accessible(let count):
            let number = String(count)
            Label(
                count == 1
                    ? String(localized: "llm.accessible.one", defaultValue: "Catálogo accesible: 1 modelo (no garantiza saldo para analizar)")
                    : String(localized: "llm.accessible.many", defaultValue: "Catálogo accesible: \(number) modelos (no garantiza saldo para analizar)"),
                systemImage: "checkmark.circle")
        case .failed(let text, let keyKept):
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.error)
                Text(keyKept
                    ? String(localized: "llm.keyKept", defaultValue: "La clave sigue guardada en este iPhone.")
                    : String(localized: "llm.keyDiscarded", defaultValue: "La clave se descartó; no quedó guardada."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case nil:
            EmptyView()
        }
    }
}
