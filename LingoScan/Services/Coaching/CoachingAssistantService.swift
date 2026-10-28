import Foundation

/// "Preguntar al asistente" con el mismo proveedor, clave y modelo del asistente de comidas (D-19). Una sola
/// petición con el contexto agregado (`CoachingRequest`); la respuesta la valida `CoachingReplyParser`.
struct CoachingAssistantService: CoachingAsking {
    let keys: LLMKeyStore
    let settings: LLMSettingsStore
    let makeProvider: @Sendable (LLMProviderID) -> any LLMProvider
    var locale: String = Locale.current.identifier

    static func live(assistant: MealAssistantServices) -> CoachingAssistantService {
        CoachingAssistantService(keys: assistant.keys, settings: assistant.settings, makeProvider: assistant.makeProvider)
    }

    func isConfigured() async -> Bool { await configured() != nil }

    func ask(_ record: CoachingRecord) async throws -> CoachingAnswer {
        guard let configured = await configured() else { throw CoachingAssistantError.notConfigured }
        let request = CoachingRequest(record: record, locale: locale)
        let reply = try await makeProvider(configured.provider).coach(request, model: configured.model, apiKey: configured.key)
        return CoachingAnswer(reply: reply, source: "\(configured.provider.displayName) · \(configured.model.displayName)")
    }

    private struct Configured {
        var provider: LLMProviderID
        var model: LLMModel
        var key: String
    }

    /// Proveedor elegido con clave guardada y modelo elegido; si falta algo, no hay asistente.
    private func configured() async -> Configured? {
        guard let provider = settings.selectedProvider(), let model = settings.selectedModel(for: provider),
              let key = try? await keys.key(for: provider), !key.isEmpty else { return nil }
        return Configured(provider: provider, model: model, key: key)
    }
}
