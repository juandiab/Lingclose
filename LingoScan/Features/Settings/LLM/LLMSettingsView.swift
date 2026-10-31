import SwiftUI

/// Ajustes › Conexiones › Asistente con IA. Muestra solo lo que corresponde al paso de `LLMSettingsViewModel`. Explica
/// que la clave es del usuario y que el proveedor cobra cada consulta; "Olvidar clave" pide confirmación.
struct LLMSettingsView: View {
    @State private var viewModel: LLMSettingsViewModel
    @State private var isConfirmingForget = false

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
                Text(String(localized: "llm.privacy", defaultValue: "La clave se guarda solo en el llavero de este iPhone. Al proveedor solo se envía lo necesario para cada consulta (por ejemplo, la foto reducida y tu descripción de una comida), nunca tu nombre."))
            }
        }
        .navigationTitle(String(localized: "llm.title", defaultValue: "Asistente con IA"))
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
        } header: {
            Text(String(localized: "llm.provider", defaultValue: "Proveedor"))
        } footer: {
            Text(String(localized: "llm.provider.footer", defaultValue: "Lo usan \"Analizar con IA\" en comidas y reportes, \"Preguntar al asistente\" en Hoy y \"Sugerir rango\". Es opcional: sin él, todo lo demás funciona igual."))
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
                String(localized: "llm.key.field", defaultValue: "Pega aquí tu clave de API"),
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
        } header: {
            Text(String(localized: "llm.key.header", defaultValue: "Clave de API"))
        } footer: {
            Text(String(localized: "llm.key.footer", defaultValue: "La clave se crea en la web del proveedor, en tu cuenta. El proveedor cobra cada consulta a esa cuenta; Lingclose no cobra nada."))
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
            } footer: {
                Text(String(localized: "llm.pick.footer", defaultValue: "El precio lo publica el proveedor por millón de tokens (trozos de texto); una consulta usa unos pocos miles. Cada modelo indica si acepta fotos y por qué se recomienda o no."))
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
            } header: {
                Text(String(localized: "llm.chosen", defaultValue: "En uso"))
            }
            Section {
                Button(String(localized: "llm.changeModel", defaultValue: "Cambiar modelo")) {
                    Task { await viewModel.changeModel() }
                }
                Button(String(localized: "llm.changeKey", defaultValue: "Cambiar clave")) {
                    viewModel.changeKey()
                }
                Button(String(localized: "llm.forgetKey", defaultValue: "Olvidar clave"), role: .destructive) {
                    isConfirmingForget = true
                }
                .confirmationDialog(
                    String(localized: "llm.forget.title", defaultValue: "¿Olvidar la clave?"),
                    isPresented: $isConfirmingForget,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "llm.forgetKey", defaultValue: "Olvidar clave"), role: .destructive) {
                        Task { await viewModel.forgetKey() }
                    }
                    Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
                } message: {
                    Text(String(localized: "llm.forget.message", defaultValue: "Se borran de este iPhone la clave y el modelo elegido. Para volver a usar el asistente tendrás que pegar la clave otra vez."))
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
                    ? String(localized: "llm.accessible.one", defaultValue: "La clave funciona: 1 modelo disponible. Comprueba en tu cuenta que tienes saldo.")
                    : String(localized: "llm.accessible.many", defaultValue: "La clave funciona: \(number) modelos disponibles. Comprueba en tu cuenta que tienes saldo."),
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
