import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Servicio completo con respuestas grabadas: respuesta válida, inválida, sin datos de Salud, cobertura
/// insuficiente, sin asistente y privacidad de la petición.
struct RangeSuggestionServiceTests {
    private let threeDays = InMemoryRangeReadings(readings: RangeFixtures.readings(hours: 72))

    @Test func validAssistantReplyBecomesTheSuggestion() async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, replies: [RangeFixtures.reply("anthropic-range")])
        let suggestion = try await env.service.suggest()
        #expect(suggestion.low == 75)
        #expect(suggestion.high == 145)
        #expect(suggestion.origin == .assistant(provider: .anthropic, modelName: env.model.displayName))
        #expect(suggestion.explanation.contains("percentil 5"))
        #expect(suggestion.assistantNote == nil)
        #expect(suggestion.readings.count == 72 * 60)
        #expect(suggestion.readings.coverageHours == 72)
        #expect(suggestion.profile.ageYears == 41)
        #expect(suggestion.profile.bodyMassIndex.map { ($0 * 10).rounded() / 10 } == 25.3)
        #expect(env.transport.requests.count == 1, "una sola llamada, sin reintentos")
    }

    @Test(arguments: LLMProviderID.allCases)
    func everyProviderParsesItsRecordedReply(provider: LLMProviderID) async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, provider: provider,
                                                      replies: [RangeFixtures.reply("\(provider.rawValue)-range")])
        let suggestion = try await env.service.suggest()
        #expect(suggestion.low == 75)
        #expect(suggestion.high == 145)
        #expect(suggestion.isAssistant)
    }

    @Test(arguments: ["anthropic-range-invalid", "anthropic-broken"])
    func invalidReplyFallsBackToStatisticsWithANote(fixture: String) async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, replies: [RangeFixtures.reply(fixture)])
        let suggestion = try await env.service.suggest()
        #expect(suggestion.origin == .statistics)
        #expect(suggestion.low == suggestion.statisticalLow)
        #expect(suggestion.high == suggestion.statisticalHigh)
        #expect(RangeSuggestionBounds.isValid(low: suggestion.low, high: suggestion.high))
        #expect(suggestion.assistantNote?.isEmpty == false)
        #expect(env.transport.requests.count == 1, "no se reintenta")
    }

    @Test func outOfBoundsReplyFromChatProvidersIsRejected() async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, provider: .gemini,
                                                      replies: [RangeFixtures.reply("gemini-range-invalid")])
        let suggestion = try await env.service.suggest()
        #expect(suggestion.origin == .statistics)
        #expect(suggestion.assistantNote != nil)
        let openai = try await RangeFixtures.makeService(readings: threeDays, provider: .openai,
                                                         replies: [RangeFixtures.reply("openai-range-invalid")])
        #expect(try await openai.service.suggest().assistantNote != nil)
    }

    @Test func providerErrorKeepsTheStatisticalProposal() async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, replies: [RangeFixtures.reply("anthropic-429", status: 429)])
        let suggestion = try await env.service.suggest()
        #expect(suggestion.origin == .statistics)
        #expect(suggestion.assistantNote?.contains(LLMError.rateLimited.description) == true)
    }

    @Test func missingHealthDataIsOmittedAndSaidSo() async throws {
        let env = try await RangeFixtures.makeService(
            readings: threeDays, health: FakeHealthProfileReader(profile: .empty), replies: [RangeFixtures.reply("anthropic-range")])
        let suggestion = try await env.service.suggest()
        #expect(suggestion.profile.isEmpty)
        #expect(suggestion.profile.missingFields == HealthProfileField.allCases)
        #expect(suggestion.healthNote == nil, "sin datos no es un error de Salud")
        let data = try #require(env.transport.requests.first?.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        #expect(body.contains("\\\"age_years\\\": null"))
        #expect(body.contains("\\\"bmi\\\": null"))
    }

    @Test func partialProfileListsOnlyWhatIsMissing() async throws {
        let partial = HealthProfile(ageYears: 35, biologicalSex: nil, weightKg: 70, heightCm: nil)
        let env = try await RangeFixtures.makeService(readings: threeDays, health: FakeHealthProfileReader(profile: partial), configured: false)
        let suggestion = try await env.service.suggest()
        #expect(suggestion.profile.missingFields == [.sex, .height])
        #expect(suggestion.profile.bodyMassIndex == nil, "sin altura no hay IMC")
    }

    @Test func healthFailureIsNotedAndSuggestionContinues() async throws {
        let env = try await RangeFixtures.makeService(
            readings: threeDays, health: FakeHealthProfileReader(error: .authorizationFailed("x 1")), configured: false)
        let suggestion = try await env.service.suggest()
        #expect(suggestion.healthNote != nil)
        #expect(suggestion.profile.isEmpty)
        #expect(suggestion.origin == .statistics)
    }

    @Test func insufficientCoverageFails() async throws {
        let env = try await RangeFixtures.makeService(readings: InMemoryRangeReadings(readings: RangeFixtures.readings(hours: 10)))
        await #expect(throws: RangeSuggestionError.insufficientCoverage(hours: 10, required: 24)) {
            _ = try await env.service.suggest()
        }
        #expect(env.transport.requests.isEmpty, "sin cobertura no se llama al asistente")
        #expect(RangeSuggestionError.insufficientCoverage(hours: 10, required: 24).description.contains("24 h"))
    }

    @Test func noReadingsAndStoreFailureAreDistinctErrors() async throws {
        let empty = try await RangeFixtures.makeService(readings: InMemoryRangeReadings(readings: []))
        await #expect(throws: RangeSuggestionError.noReadings) { _ = try await empty.service.suggest() }
        let broken = try await RangeFixtures.makeService(readings: FailingRangeReadings())
        await #expect(throws: RangeSuggestionError.store("Boom")) { _ = try await broken.service.suggest() }
    }

    @Test func withoutConfiguredAssistantOnlyStatisticsAreUsed() async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, configured: false)
        let suggestion = try await env.service.suggest()
        #expect(suggestion.origin == .statistics)
        #expect(suggestion.assistantNote == nil)
        #expect(env.transport.requests.isEmpty)
        // El patrón de 10 valores reparte un 10 % a cada uno: p5 cae en 82 (→ 80) y p95 en 141 (→ 140).
        #expect(suggestion.low == 80)
        #expect(suggestion.high == 140)
        // La explicación estadística está localizada (es/en): se compara con la que genera el servicio.
        #expect(suggestion.explanation == RangeSuggestionService.statisticalExplanation(summary: suggestion.readings))
        #expect(!suggestion.explanation.isEmpty)
    }

    @Test func requestCarriesOnlyAggregatesNeverRawReadings() async throws {
        let env = try await RangeFixtures.makeService(readings: threeDays, replies: [RangeFixtures.reply("anthropic-range")])
        _ = try await env.service.suggest()
        let request = try #require(env.transport.requests.first)
        let data = try #require(request.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        #expect(!body.contains("range-test-session"), "sin identificador de sesión")
        #expect(!body.contains("record_id"))
        #expect(!body.contains("measured_at"))
        #expect(!body.contains("1800000000"), "sin marcas de tiempo")
        #expect(!body.contains("lifeCount") && !body.contains("life_count"))
        #expect(body.contains("\\\"p5\\\""))
        #expect(body.contains("\\\"statistical_proposal\\\""))
        #expect(body.contains("NO determinan un rango de glucosa validado"), "la instrucción sobre edad, peso y altura va en el prompt")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == LLMFixtures.testKey)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tool = try #require((json["tools"] as? [[String: Any]])?.first)
        #expect(tool["name"] as? String == RangeSuggestionPrompt.toolName)
        #expect(((tool["input_schema"] as? [String: Any])?["required"] as? [String]) == ["low_mgdl", "high_mgdl", "explanation"])
    }

    @Test func userTextHasOneDecimalAndNullsForMissingProfile() {
        let request = RangeSuggestionRequest(
            windowDays: 14, readingCount: 100, coverageHours: 48.25, percentile5: 71.26, percentile95: 143.75, median: 100,
            mean: 101.333, standardDeviation: 15.55, statisticalLow: 70, statisticalHigh: 145, ageYears: nil,
            biologicalSex: "female", bodyMassIndex: nil, locale: "es-CO")
        let text = request.userText
        #expect(text.contains("\"p5\": 71.3"))
        #expect(text.contains("\"coverage_hours\": 48.2") || text.contains("\"coverage_hours\": 48.3"))
        #expect(text.contains("\"age_years\": null"))
        #expect(text.contains("\"biological_sex\": \"female\""))
        #expect(text.contains("\"bmi\": null"))
    }
}

@MainActor
struct RangeSuggestionViewModelTests {
    @Test func readySuggestionIsClampedToSettingsOnAccept() async {
        var sample = PreviewRangeSuggester.sample
        sample.low = 50
        sample.high = 110
        let model = RangeSuggestionViewModel(suggester: PreviewRangeSuggester(result: .success(sample), delay: .zero))
        #expect(model.phase == .loading)
        #expect(!model.canAccept)
        await model.load()
        #expect(model.canAccept)
        #expect(model.applied?.low == 50)
        #expect(model.applied?.high == 120, "Ajustes solo edita la alta desde 120")
        #expect(model.isAdjustedForSettings)
    }

    @Test func failureShowsTheReason() async {
        let model = RangeSuggestionViewModel(
            suggester: PreviewRangeSuggester(result: .failure(.insufficientCoverage(hours: 5, required: 24)), delay: .zero))
        await model.load()
        guard case .failed(let message) = model.phase else { Issue.record("esperaba failed"); return }
        #expect(message.contains("24 h"))
        #expect(model.applied == nil)
    }
}
