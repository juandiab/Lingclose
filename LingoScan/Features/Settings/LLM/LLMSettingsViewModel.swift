import Foundation
import Observation

/// Ajustes → Asistente de comidas, como máquina de estados (orden fijo pedido por Juampa):
///
/// 1. `sinClave`: proveedor + campo de clave + "Guardar y comprobar". Ningún listado de modelos.
/// 2. `comprobando`: progreso. Si falla vuelve a `sinClave` con el error.
/// 3. `catalogo`: la clave quedó probada; lista con búsqueda para elegir.
/// 4. `elegido`: solo proveedor, "Clave guardada ••••", el modelo elegido y los botones de cambio.
///
/// Con clave y modelo guardados se entra directamente en `elegido`, sin red. La clave nunca se expone: ni
/// en el estado ni en los mensajes; `keyInput` se vacía al guardar.
@MainActor
@Observable
final class LLMSettingsViewModel {
    enum Step: Equatable {
        case sinClave
        case comprobando
        case catalogo
        case elegido
    }

    enum Message: Equatable {
        case accessible(count: Int)
        /// `keyKept`: la clave sigue guardada (error de red o del proveedor) o se descartó (clave rechazada).
        case failed(String, keyKept: Bool)
    }

    private(set) var step: Step = .sinClave
    private(set) var provider: LLMProviderID
    var keyInput = ""
    private(set) var hasSavedKey = false
    private(set) var models: [LLMModel] = []
    private(set) var selectedModel: LLMModel?
    private(set) var message: Message?
    var searchText = ""

    @ObservationIgnored private let keys: LLMKeyStore
    @ObservationIgnored private let settings: LLMSettingsStore
    @ObservationIgnored private let makeProvider: @Sendable (LLMProviderID) -> any LLMProvider

    init(
        keys: LLMKeyStore,
        settings: LLMSettingsStore,
        makeProvider: @escaping @Sendable (LLMProviderID) -> any LLMProvider
    ) {
        self.keys = keys
        self.settings = settings
        self.makeProvider = makeProvider
        provider = settings.selectedProvider() ?? .anthropic
    }

    /// Para el `Picker`: leer es el proveedor actual; escribir lo cambia y recarga su estado.
    var providerChoice: LLMProviderID {
        get { provider }
        set { Task { await selectProvider(newValue) } }
    }

    var canSaveKey: Bool {
        step == .sinClave && !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Hay clave guardada pero ningún modelo elegido: se ofrece "Comprobar y listar".
    var needsModelChoice: Bool { step == .sinClave && hasSavedKey && selectedModel == nil }

    /// Con clave y modelo guardados se puede cancelar el cambio de clave.
    var canCancelKeyChange: Bool { step == .sinClave && hasSavedKey && selectedModel != nil }

    var filteredModels: [LLMModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.id.localizedStandardContains(query) || $0.displayName.localizedStandardContains(query)
        }
    }

    // MARK: Entrada a la pantalla

    /// Lee clave y modelo guardados del proveedor actual. Nunca llama a la red.
    func load() async {
        let current = provider
        let saved = await keys.hasKey(for: current)
        guard provider == current else { return }
        hasSavedKey = saved
        selectedModel = settings.selectedModel(for: current)
        models = []
        message = nil
        searchText = ""
        keyInput = ""
        step = saved && selectedModel != nil ? .elegido : .sinClave
    }

    func selectProvider(_ newProvider: LLMProviderID) async {
        guard newProvider != provider else { return }
        provider = newProvider
        settings.setSelectedProvider(newProvider)
        await load()
    }

    // MARK: 1 → 2 → 3

    /// "Guardar y comprobar": guarda la clave y pide el catálogo autenticado.
    func saveAndCheck() async {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard step == .sinClave, !key.isEmpty else { return }
        do {
            try await keys.save(key, for: provider)
        } catch {
            message = .failed(
                String(localized: "llm.error.keychain", defaultValue: "No se pudo guardar la clave en el llavero de este iPhone."),
                keyKept: false)
            return
        }
        keyInput = ""
        hasSavedKey = true
        settings.setSelectedProvider(provider)
        await check(apiKey: key, onFailure: .sinClave)
    }

    /// "Comprobar y listar": vuelve a probar la clave ya guardada.
    func checkSavedKey() async {
        guard step == .sinClave, hasSavedKey, let key = try? await keys.key(for: provider) else { return }
        await check(apiKey: key, onFailure: .sinClave)
    }

    /// "Actualizar catálogo" dentro del paso 3.
    func refreshCatalog() async {
        guard step == .catalogo, let key = try? await keys.key(for: provider) else { return }
        await check(apiKey: key, onFailure: .catalogo)
    }

    private func check(apiKey: String, onFailure: Step) async {
        let requested = provider
        step = .comprobando
        message = nil
        do {
            let result = try await makeProvider(requested).listModels(apiKey: apiKey)
            guard provider == requested else { return }
            models = Self.sorted(result)
            if let chosen = selectedModel, let fresh = result.first(where: { $0.id == chosen.id }) {
                selectedModel = fresh
                settings.setSelectedModel(fresh)
            }
            message = .accessible(count: result.count)
            searchText = ""
            step = .catalogo
        } catch {
            guard provider == requested else { return }
            let text = (error as? LLMError)?.description ?? error.localizedDescription
            var keyKept = true
            if case LLMError.unauthorized = error, onFailure == .sinClave {
                // Clave rechazada: se descarta para no dejar guardada una clave inútil.
                try? await keys.delete(for: requested)
                hasSavedKey = false
                keyKept = false
            }
            message = .failed(text, keyKept: keyKept)
            step = onFailure
        }
    }

    // MARK: 3 → 4

    /// Tocar un modelo lo elige, lo guarda y pliega la lista.
    func choose(_ model: LLMModel) {
        guard step == .catalogo, model.provider == provider else { return }
        settings.setSelectedProvider(provider)
        settings.setSelectedModel(model)
        selectedModel = model
        searchText = ""
        step = .elegido
    }

    // MARK: Desde 4

    /// "Cambiar modelo": vuelve al catálogo ya descargado; si aún no se descargó en esta sesión, lo pide una vez.
    func changeModel() async {
        guard step == .elegido else { return }
        if !models.isEmpty {
            searchText = ""
            step = .catalogo
        } else if let key = try? await keys.key(for: provider) {
            await check(apiKey: key, onFailure: .elegido)
        }
    }

    /// "Cambiar clave": vuelve al paso 1 sin borrar nada todavía.
    func changeKey() {
        guard step == .elegido else { return }
        message = nil
        step = .sinClave
    }

    func cancelKeyChange() {
        guard canCancelKeyChange else { return }
        keyInput = ""
        message = nil
        step = .elegido
    }

    /// "Olvidar clave": borra la clave y el modelo elegido de este proveedor.
    func forgetKey() async {
        try? await keys.delete(for: provider)
        settings.clearSelectedModel(for: provider)
        hasSavedKey = false
        selectedModel = nil
        models = []
        message = nil
        keyInput = ""
        searchText = ""
        step = .sinClave
    }

    private static func sorted(_ models: [LLMModel]) -> [LLMModel] {
        func rank(_ model: LLMModel) -> Int {
            switch model.recommendation {
            case .recommended: 0
            case .unknown: 1
            case .notRecommended: 2
            }
        }
        return models.sorted { (rank($0), $0.displayName.lowercased()) < (rank($1), $1.displayName.lowercased()) }
    }
}
