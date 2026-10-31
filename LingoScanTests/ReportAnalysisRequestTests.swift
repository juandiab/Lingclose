import CryptoKit
import Foundation
import Testing
@testable import LingoScan

/// Contenido y huella de la petición de análisis (T-27d): estable, sin texto libre del diario.
struct ReportAnalysisRequestTests {
    @Test func sha256IsStableAndMatchesTheSentMessage() throws {
        let a = try ReportAnalysisRequest(bundle: ReportAnalysisFixtures.bundle(), locale: "es-CO")
        let b = try ReportAnalysisRequest(bundle: ReportAnalysisFixtures.bundle(), locale: "es-CO")
        #expect(a.sha256 == b.sha256)
        #expect(a.sha256.count == 64)
        #expect(a.sha256 == SHA256.hash(data: Data(a.userText.utf8)).map { String(format: "%02x", $0) }.joined())
        let other = try ReportAnalysisRequest(bundle: ReportAnalysisFixtures.bundle(days: 14), locale: "es-CO")
        #expect(other.sha256 != a.sha256)
    }

    @Test func promptCarriesNoFreeTextFromTheDiary() throws {
        let request = try ReportAnalysisRequest(bundle: ReportAnalysisFixtures.bundle(), locale: "es-CO")
        let prompt = ReportAnalysisPrompt.prompt(for: request)
        for text in [prompt.userText, prompt.system, request.snapshotJSON] {
            #expect(!text.contains(ReportAnalysisFixtures.freeText))
            #expect(!text.contains("Gertrudis"))
            #expect(!text.contains("America/Bogota"))
            #expect(!text.contains("test-app"))
        }
        // Sí lleva cifras del reporte y los reportes con datos.
        #expect(request.topicsWithData.contains(.summary))
        #expect(request.topicsWithData.contains(.hourlyProfile))
        #expect(prompt.userText.contains("summary"))
        #expect(prompt.userText.contains("hourly_profile"))
        #expect(prompt.userText.contains("\"carbs_g\""))
    }

    @Test func snapshotFitsTheSizeBudget() throws {
        let request = try ReportAnalysisRequest(bundle: ReportAnalysisFixtures.bundle(days: 30), locale: "es-CO")
        #expect(request.snapshotJSON.utf8.count <= 60_000)
        #expect(request.payloadBytes >= request.snapshotJSON.utf8.count)
    }

    @Test func systemPromptSetsTheGuardrails() {
        let system = ReportAnalysisPrompt.systemPrompt(locale: "pt-BR")
        #expect(system.contains("pt-BR"))
        #expect(system.contains("NO usa insulina"))
        #expect(system.contains("Prohibido diagnosticar"))
        #expect(system.contains("no consejo médico"))
        #expect(system.contains("what_to_try"))
    }

    @Test func topicsWithoutDataAreListedSeparately() throws {
        let bundle = ReportAnalysisFixtures.bundle(withDiary: false)
        let request = try ReportAnalysisRequest(bundle: bundle, locale: "es-CO")
        #expect(request.topicsWithData.contains(.summary))
        #expect(request.topicsWithoutData.contains(.meals))
        #expect(request.topicsWithoutData.contains(.exercise))
        #expect(Set(request.topicsWithData).isDisjoint(with: request.topicsWithoutData))
    }
}
