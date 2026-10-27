import Foundation

/// Proveedor y modelo elegidos para el asistente de comidas, en `UserDefaults`. Nunca la clave
/// (esa vive en `LLMKeyStore`). El modelo se guarda por proveedor para no perderlo al cambiar.
struct LLMSettingsStore: Sendable {
    static let providerKey = "lingoscan.llm.provider.v1"
    static func modelKey(for provider: LLMProviderID) -> String { "lingoscan.llm.model.v1.\(provider.rawValue)" }

    /// `UserDefaults` es seguro entre hilos (documentado por Apple), aunque no esté marcado `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectedProvider() -> LLMProviderID? {
        defaults.string(forKey: Self.providerKey).flatMap(LLMProviderID.init(rawValue:))
    }

    func setSelectedProvider(_ provider: LLMProviderID?) {
        if let provider { defaults.set(provider.rawValue, forKey: Self.providerKey) }
        else { defaults.removeObject(forKey: Self.providerKey) }
    }

    func selectedModel(for provider: LLMProviderID) -> LLMModel? {
        guard let data = defaults.data(forKey: Self.modelKey(for: provider)),
              let model = try? JSONDecoder().decode(LLMModel.self, from: data),
              model.provider == provider else { return nil }
        return model
    }

    func setSelectedModel(_ model: LLMModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: Self.modelKey(for: model.provider))
    }

    func clearSelectedModel(for provider: LLMProviderID) {
        defaults.removeObject(forKey: Self.modelKey(for: provider))
    }
}
