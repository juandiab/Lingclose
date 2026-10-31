import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// Análisis de reportes con IA (T-27d) con respuestas grabadas: válida, rechazada, truncada o incorrecta, sin
/// configurar, historial y borrado. Ninguna llamada real.
@MainActor
struct ReportAnalysisServiceTests {
    private let bundle = ReportAnalysisFixtures.bundle()

    @Test func validReplyIsParsedAndStoredAsSucceeded() async throws {
        let env = try await ReportAnalysisFixtures.makeService(
            replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText())])
        await env.service.run(bundle)

        guard case .done(let reply) = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        #expect(reply.sections.count == 2)
        #expect(reply.sections.first?.whatToTry == "Mantén el horario de las cenas una semana y compara.")
        #expect(reply.questionsToExplore.count == 1)
        #expect(env.transport.requests.count == 1, "una sola petición, sin reintentos")

        let records = try await env.store.recentReportAnalyses(limit: 10)
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.status == .succeeded)
        #expect(record.provider == "anthropic")
        #expect(record.model == "claude-haiku-5-5")
        #expect(record.periodStart == bundle.period.start && record.periodEnd == bundle.period.end)
        #expect(ReportAnalysisService.decode(record.responseJSON) == reply)
        let request = try ReportAnalysisRequest(bundle: bundle, locale: "es-CO")
        #expect(record.requestSHA256 == request.sha256)
        #expect(env.service.history.map(\.id) == [record.id])
    }

    @Test func requestAsksForALongGuideWithTheReportSchema() async throws {
        let env = try await ReportAnalysisFixtures.makeService(
            replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText())])
        await env.service.run(bundle)
        let data = try #require(env.transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["max_tokens"] as? Int == 4000)
        let body = try #require(String(data: data, encoding: .utf8))
        #expect(body.contains("give_report_analysis"))
        #expect(body.contains("questions_to_explore"))
        #expect(!body.contains(LLMFixtures.testKey))
        #expect(env.transport.requests.first?.timeoutInterval == ReportAnalysisClient.timeout)
    }

    @Test(arguments: LLMProviderID.allCases)
    func everyProviderParsesItsReply(provider: LLMProviderID) async throws {
        let env = try await ReportAnalysisFixtures.makeService(
            provider: provider, replies: [ReportAnalysisFixtures.reply(for: provider, text: ReportAnalysisFixtures.replyText())])
        await env.service.run(bundle)
        guard case .done(let reply) = env.service.state else { Issue.record("\(provider): \(env.service.state)"); return }
        #expect(reply.sections.count == 2)
        #expect(env.transport.requests.count == 1)
        let data = try #require(env.transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        switch provider {
        case .gemini:
            #expect((json["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int == 8000)
        case .openai:
            #expect(json["max_completion_tokens"] as? Int == 4000)
        default:
            #expect(json["max_tokens"] as? Int == 4000)
        }
    }

    @Test func replyMentioningInsulinIsRejectedWhole() async throws {
        let object = ReportAnalysisFixtures.replyObject(overview: "Conviene ajustar la insulina tras la cena.")
        let env = try await ReportAnalysisFixtures.makeService(
            replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText(object))])
        await env.service.run(bundle)
        guard case .rejected(let reason) = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        #expect(reason.contains("insulin"))
        #expect(env.transport.requests.count == 1, "no se reintenta")
        let record = try #require(try await env.store.recentReportAnalyses(limit: 10).first)
        #expect(record.status == .rejected)
        #expect(record.responseJSON == nil, "la respuesta rechazada no se guarda")
        #expect(record.error?.contains("insulin") == true)
    }

    @Test func diagnosisInsideASectionRejectsTheWholeReply() async throws {
        var object = ReportAnalysisFixtures.replyObject()
        var sections = object["sections"] as! [[String: Any]]
        sections[1]["why_it_may_happen"] = "Podría indicar prediabetes."
        object["sections"] = sections
        let env = try await ReportAnalysisFixtures.makeService(
            replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText(object))])
        await env.service.run(bundle)
        guard case .rejected = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
    }

    @Test func truncatedOrBrokenJSONFails() async throws {
        let cut = String(ReportAnalysisFixtures.replyText().prefix(120))
        let env = try await ReportAnalysisFixtures.makeService(replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: cut)])
        await env.service.run(bundle)
        guard case .failed = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        let record = try #require(try await env.store.recentReportAnalyses(limit: 10).first)
        #expect(record.status == .failed)
        #expect(record.responseJSON == nil)
        #expect(env.transport.requests.count == 1)
    }

    @Test func maxTokensStopReasonFails() async throws {
        let env = try await ReportAnalysisFixtures.makeService(
            replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText(), truncated: true)])
        await env.service.run(bundle)
        guard case .failed(let reason) = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        #expect(reason.contains("max_tokens"))
        #expect(try await env.store.recentReportAnalyses(limit: 10).first?.status == .failed)
    }

    @Test func replyWithoutSectionsFails() async throws {
        var object = ReportAnalysisFixtures.replyObject()
        object["sections"] = []
        let env = try await ReportAnalysisFixtures.makeService(
            replies: [ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText(object))])
        await env.service.run(bundle)
        guard case .failed = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
    }

    @Test func providerErrorFailsWithoutRetry() async throws {
        let env = try await ReportAnalysisFixtures.makeService(replies: [FixtureTransport.Reply(status: 429, body: Data("{}".utf8))])
        await env.service.run(bundle)
        guard case .failed = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        #expect(env.transport.requests.count == 1)
    }

    @Test func withoutAssistantNothingIsSent() async throws {
        let env = try await ReportAnalysisFixtures.makeService(configured: false)
        await env.service.prepare(for: bundle)
        #expect(env.service.isConfigured == false)
        await env.service.run(bundle)
        guard case .failed(let reason) = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        #expect(reason == ReportAnalysisError.notConfigured.description)
        #expect(env.transport.requests.isEmpty)
        #expect(try await env.store.recentReportAnalyses(limit: 10).isEmpty)
    }

    @Test func historyGroupsBySpanAndCanBeDeleted() async throws {
        let ok = ReportAnalysisFixtures.reply(for: .anthropic, text: ReportAnalysisFixtures.replyText())
        let env = try await ReportAnalysisFixtures.makeService(replies: [ok, ok])
        await env.service.prepare(for: bundle)
        #expect(env.service.history.isEmpty)
        #expect(env.service.outgoing != nil)
        await env.service.run(bundle)
        await env.service.run(bundle)
        #expect(env.service.history.count == 2)
        #expect(env.service.history.map(\.id) == ["analysis-2", "analysis-1"])

        // Otro tramo (14 días) no ve los análisis de 7 días.
        let other = ReportAnalysisFixtures.bundle(days: 14)
        await env.service.refreshHistory(for: other.period)
        #expect(env.service.history.isEmpty)
        await env.service.refreshHistory(for: bundle.period)

        let first = try #require(env.service.history.last)
        env.service.show(first)
        guard case .done = env.service.state else { Issue.record("estado: \(env.service.state)"); return }
        #expect(env.service.shownRecordID == first.id)
        await env.service.delete(first)
        #expect(env.service.history.map(\.id) == ["analysis-2"])
        #expect(env.service.state == .idle)
        #expect(try await env.store.recentReportAnalyses(limit: 10).count == 1)
    }

    @Test func costEstimateUsesPublishedPricingOnly() async throws {
        let request = try ReportAnalysisRequest(bundle: bundle, locale: "es-CO")
        let free = LLMFixtures.model(for: .anthropic)
        #expect(ReportAnalysisCostEstimate(request: request, model: free).usd == nil)
        var priced = free
        priced.pricing = ModelPricing(inputUSDPerMTok: 1, outputUSDPerMTok: 5, source: "test", asOf: "2026-10")
        let estimate = ReportAnalysisCostEstimate(request: request, model: priced)
        let expected = (Double(estimate.inputTokens) * 1 + Double(estimate.outputTokens) * 5) / 1_000_000
        #expect(estimate.usd == expected)
        #expect(estimate.outputTokens == 4000)
        #expect(estimate.inputTokens > 1000)
    }
}
