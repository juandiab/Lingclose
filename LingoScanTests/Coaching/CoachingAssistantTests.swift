import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// "Preguntar al asistente" (T-25) con respuestas grabadas: válidas, inválidas (insulina), sin asistente y
/// privacidad de la petición. Ninguna llamada real.
struct CoachingAssistantTests {
    @Test func anthropicValidReplyIsParsed() async throws {
        let env = try await CoachingFixtures.makeService(replies: [CoachingFixtures.reply("anthropic-coach")])
        let answer = try await env.service.ask(CoachingFixtures.record())
        #expect(answer.reply.summary.hasPrefix("Tras una comida"))
        #expect(answer.reply.suggestions.count == 3)
        #expect(answer.reply.suggestions.first == .init(title: "Pausa activa", body: "Si estás sentado, levántate y camina un par de minutos cada media hora."))
        #expect(answer.reply.caution == nil)
        #expect(answer.source.contains("claude-haiku-5-5"))
        #expect(env.transport.requests.count == 1, "una sola petición, sin reintentos")
        let body = try #require(env.transport.requests.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("give_wellbeing_suggestions"))
    }

    @Test func openAIValidReplyIsParsed() async throws {
        let env = try await CoachingFixtures.makeService(provider: .openai, replies: [CoachingFixtures.reply("openai-coach")])
        let answer = try await env.service.ask(CoachingFixtures.record())
        #expect(answer.reply.suggestions.map(\.title) == ["Pausa activa", "Cena ligera", "Mira la tendencia"])
        let request = try #require(env.transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("\"json_schema\""))
        #expect(body.contains("wellbeing_suggestions"))
    }

    @Test(arguments: LLMProviderID.allCases)
    func everyProviderParsesItsRecordedReply(provider: LLMProviderID) async throws {
        let env = try await CoachingFixtures.makeService(provider: provider, replies: [CoachingFixtures.reply("\(provider.rawValue)-coach")])
        let answer = try await env.service.ask(CoachingFixtures.record())
        #expect(answer.reply.suggestions.count == 3)
        #expect(env.transport.requests.count == 1)
    }

    @Test(arguments: ["anthropic-coach-insulin", "openai-coach-insulin"])
    func replyMentioningInsulinIsRejected(fixture: String) async throws {
        let provider: LLMProviderID = fixture.hasPrefix("openai") ? .openai : .anthropic
        let env = try await CoachingFixtures.makeService(provider: provider, replies: [CoachingFixtures.reply(fixture)])
        await #expect {
            _ = try await env.service.ask(CoachingFixtures.record())
        } throws: { error in
            guard case .invalidResponse(let detail) = error as? LLMError else { return false }
            return detail.contains("insulin") || detail.contains("medic")
        }
        #expect(env.transport.requests.count == 1, "no se reintenta")
    }

    @Test func withoutAssistantNothingIsSent() async throws {
        let env = try await CoachingFixtures.makeService(configured: false)
        #expect(await env.service.isConfigured() == false)
        await #expect(throws: CoachingAssistantError.notConfigured) {
            _ = try await env.service.ask(CoachingFixtures.record())
        }
        #expect(env.transport.requests.isEmpty)
    }

    @Test func requestCarriesOnlyAggregates() async throws {
        let env = try await CoachingFixtures.makeService(replies: [CoachingFixtures.reply("anthropic-coach")])
        _ = try await env.service.ask(CoachingFixtures.record())
        let data = try #require(env.transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        for expected in ["\"kind\" : \"high\"", "\"value_mgdl\" : 165", "\"local_hour\" : 14", "\"time_in_range_today_pct\" : 82",
                         "\"carbs_g\" : 72", "\"kcal\" : 640", "\"protein_g\" : 24", "\"fat_g\" : 21",
                         "\"minutes_ago\" : 45", "\"kind\" : \"Correr\"", "\"duration_min\" : 30", "tips_already_shown"] {
            #expect(text.contains(expected), "falta \(expected)")
        }
        // Nada de identificadores, fechas ni la clave.
        let whole = try #require(String(data: data, encoding: .utf8))
        #expect(!whole.contains("lingoscan.alert"))
        #expect(!whole.contains("1800000000"))
        #expect(!whole.contains(LLMFixtures.testKey))
        let system = try #require(json["system"] as? String)
        #expect(system.contains("NO tiene diabetes"))
        #expect(system.contains("profesional de la salud"))
        #expect(system.contains("insulina"))
    }

    @Test func requestDropsExerciseAndMealWhenTheContextHasNone() {
        let context = CoachingContext(kind: .low, value: 62, hour: 3)
        var record = CoachingFixtures.record(context: context)
        record.exerciseKind = "Correr"
        let request = CoachingRequest(record: record, locale: "es-CO")
        #expect(request.meal == nil)
        #expect(request.exerciseKind == nil)
        #expect(request.userText.contains("\"last_meal\" : null"))
        #expect(request.userText.contains("\"last_exercise\" : null"))
        #expect(request.shownTips.count == 2)
    }

    // MARK: - Botón "Preguntar al asistente"

    @Test @MainActor func askButtonOnlyWithConfiguredAssistant() async throws {
        let store = CoachingFixtures.store()
        store.save(CoachingFixtures.record(openedAt: .now))
        let without = try await CoachingFixtures.makeService(configured: false)
        let controller = CoachingController(store: store, assistant: without.service)
        await controller.refresh()
        #expect(controller.record != nil)
        #expect(controller.canAskAssistant == false, "sin asistente configurado el botón no aparece")

        let with = try await CoachingFixtures.makeService()
        let configured = CoachingController(store: store, assistant: with.service)
        await configured.refresh()
        #expect(configured.canAskAssistant)
        #expect(with.transport.requests.isEmpty, "comprobar la configuración no llama al proveedor")
    }
}
