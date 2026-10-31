import CryptoKit
import Foundation
import LingoCore
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

    // MARK: - T-33: contexto opcional

    private func context(for bundle: ReportBundle, events: [DiaryEvent], sharing: ReportAnalysisSharing) -> (ReportSnapshot, ReportAnalysisContext?) {
        let snapshot = bundle.snapshot.compact()
        let records = Dictionary(uniqueKeysWithValues: events.filter { $0.kind == .meal }
            .map { ($0.eventID, ReportAnalysisContextFixtures.record(for: $0)) })
        let context = ReportAnalysisContextBuilder.build(
            snapshot: snapshot, events: events, nutrition: records, sleep: ReportAnalysisContextFixtures.nights(3),
            steps: ReportAnalysisContextFixtures.steps(3), profile: ReportAnalysisContextFixtures.profile,
            body: ReportAnalysisContextFixtures.body(), sharing: sharing)
        return (snapshot, context)
    }

    /// Con todo apagado el mensaje es el de T-27d más una sola línea de cabecera ("Contexto opcional incluido: ninguno").
    @Test func everythingOffOnlyAddsTheHeaderLine() throws {
        let request = try ReportAnalysisRequest(bundle: ReportAnalysisFixtures.bundle(), locale: "es-CO")
        #expect(request.context == nil && request.contextJSON == nil && request.contextBytes == 0)
        func list(_ topics: [ReportAnalysisTopic]) -> String {
            topics.isEmpty ? "ninguno" : topics.map(\.rawValue).joined(separator: ", ")
        }
        let before = """
        Reporte de glucosa de \(request.periodDays) días (sin lecturas individuales identificables ni texto libre).
        Reportes con datos suficientes (una sección cada uno): \(list(request.topicsWithData))
        Reportes sin datos suficientes (no escribas sección): \(list(request.topicsWithoutData))
        Datos (JSON):
        \(request.snapshotJSON)
        """
        let withoutHeader = request.userText.replacingOccurrences(of: "Contexto opcional incluido: ninguno\n", with: "")
        #expect(withoutHeader == before)
        #expect(!request.userText.contains("Contexto opcional (JSON)"))

        // Construida con el contexto `nil` explícito: el mismo mensaje y el mismo hash.
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents()
        let (snapshot, off) = context(for: bundle, events: events, sharing: .none)
        #expect(off == nil)
        let explicit = try ReportAnalysisRequest(bundle: bundle, snapshot: snapshot, locale: "es-CO", context: off)
        #expect(explicit.userText == (try ReportAnalysisRequest(bundle: bundle, locale: "es-CO")).userText)
    }

    @Test func mealsOnCarryNamesAndMacrosButNoDiaryText() throws {
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents()
        let (snapshot, meals) = context(for: bundle, events: events, sharing: ReportAnalysisSharing(meals: true))
        let request = try ReportAnalysisRequest(bundle: bundle, snapshot: snapshot, locale: "es-CO", context: meals)
        let text = request.userText
        #expect(text.contains("Contexto opcional incluido: comidas con nombre\n"))
        #expect(text.contains("Contexto opcional (JSON):\n{"))
        #expect(text.contains(ReportAnalysisContextFixtures.mealName))
        #expect(text.contains("\"kcal\":642.3") && text.contains("\"protein_g\":32") && text.contains("\"fat_g\":17.5"))
        #expect(!text.contains(ReportAnalysisFixtures.freeText))
        #expect(!text.contains("\"sleep\"") && !text.contains("\"profile\""))
        #expect(request.contextBytes > 0 && request.payloadBytes > request.snapshotJSON.utf8.count + request.contextBytes)
        // El snapshot no cambia por llevar contexto.
        #expect(request.snapshotJSON == (try ReportAnalysisRequest(bundle: bundle, locale: "es-CO")).snapshotJSON)
    }

    @Test func sha256CoversTheContext() throws {
        let (bundle, events) = ReportAnalysisFixtures.bundleWithEvents()
        let off = try ReportAnalysisRequest(bundle: bundle, locale: "es-CO")
        let (snapshot, meals) = context(for: bundle, events: events, sharing: ReportAnalysisSharing(meals: true))
        let (_, everything) = context(for: bundle, events: events,
                                      sharing: ReportAnalysisSharing(meals: true, sleepActivity: true, profile: true))
        let a = try ReportAnalysisRequest(bundle: bundle, snapshot: snapshot, locale: "es-CO", context: meals)
        let b = try ReportAnalysisRequest(bundle: bundle, snapshot: snapshot, locale: "es-CO", context: everything)
        #expect(Set([off.sha256, a.sha256, b.sha256]).count == 3)
        #expect(a.sha256 == SHA256.hash(data: Data(a.userText.utf8)).map { String(format: "%02x", $0) }.joined())
        #expect(b.userText.contains("Contexto opcional incluido: comidas con nombre, sueño, pasos, perfil"))
        #expect(!b.userText.contains("America/Bogota") && !b.userText.contains("test-app"))
        for event in events { #expect(!b.userText.contains(event.eventID)) }
        // Extracto para docs/T-33.md (datos inventados).
        print("T33-EXAMPLE-BEGIN\n" + (b.contextJSON ?? "") + "\nT33-EXAMPLE-END")
    }

    @Test func systemPromptExplainsAndForbidsWeightLabels() {
        let system = ReportAnalysisPrompt.systemPrompt(locale: "es-CO")
        #expect(system.contains("key_takeaways"))
        #expect(system.contains("frase de conclusión"))
        #expect(system.contains("Contexto opcional"))
        #expect(system.contains("prohibido etiquetarlos"))
        #expect(system.contains("7000 tokens"))
        let schema = ReportAnalysisPrompt.strictSchema()
        #expect((schema["required"] as? [String])?.first == "key_takeaways")
    }
}
