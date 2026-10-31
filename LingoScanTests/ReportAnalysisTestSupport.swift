import Foundation
import LingoCore
@testable import LingoScan

/// Datos y servicios sintéticos de T-27d: un reporte inventado, respuestas del proveedor fijas, servicio con Llavero y
/// ajustes en memoria, `FixtureTransport` y una base SQLite temporal. Ni clave real, ni red, ni datos reales.
enum ReportAnalysisFixtures {
    static let bogota = TimeZone(identifier: "America/Bogota")!
    static let end = UTCInstant(epochSeconds: 1_800_000_000)
    static let freeText = "arepa secreta de la abuela Gertrudis"

    /// Días de lecturas cada minuto con una onda diaria, y comidas/ejercicio con texto libre inventado.
    static func bundle(days: Int = 7, withDiary: Bool = true) -> ReportBundle {
        let period = ReportPeriod.last(days, endingAt: end, timeZone: bogota)
        let from = period.dataStart.epochSeconds
        let samples = stride(from: from, to: end.epochSeconds, by: 60).map { t -> BasicStats.Sample in
            let minuteOfDay = Double((t / 60) % 1440)
            let wave = 110 + 35 * sin(minuteOfDay / 1440 * 2 * .pi)
            return BasicStats.Sample(measuredAt: UTCInstant(epochSeconds: t), valueMgdl: Int(wave.rounded()))
        }
        var events: [DiaryEvent] = []
        if withDiary {
            for day in 0..<days {
                let noon = period.start.adding(seconds: Int64(day) * 86_400 + 17 * 3_600)
                events.append(event(.meal, at: noon, carbs: 60, text: freeText))
                events.append(event(.exercise, at: noon.adding(seconds: 4 * 3_600), duration: 30, text: freeText))
                events.append(event(.note, at: noon, text: freeText))
            }
        }
        return ReportBuilder.build(samples: samples, events: events, period: period)
    }

    static func event(_ kind: DiaryEventKind, at: UTCInstant, carbs: Double? = nil, duration: Int? = nil, text: String?) -> DiaryEvent {
        DiaryEvent(eventID: UUID().uuidString.lowercased(), kind: kind, at: at, tz: "America/Bogota", durationMin: duration,
                   carbsG: carbs, text: text, createdAt: at, updatedAt: at, editID: UUID().uuidString.lowercased(),
                   editedByAppID: "test-app", synthetic: true)
    }

    /// Cuerpo `ReportAnalysisReply` válido, como diccionario JSON.
    static func replyObject(overview: String = "Tu glucosa pasó la mayor parte del tiempo dentro del rango de referencia.") -> [String: Any] {
        [
            "overview": overview,
            "sections": [
                [
                    "title": "Resumen del período",
                    "what_the_data_shows": "El 91 % de las lecturas estuvo dentro del rango de referencia.",
                    "why_it_may_happen": "Comidas regulares y movimiento diario suelen dar curvas estables.",
                    "what_to_try": "Mantén el horario de las cenas una semana y compara.",
                    "what_to_watch": "Mira si las subidas de la tarde se repiten.",
                ],
                [
                    "title": "Perfil por hora",
                    "what_the_data_shows": "La mediana sube entre las 16:00 y las 18:00.",
                    "why_it_may_happen": "Puede coincidir con la merienda.",
                    "what_to_try": "Prueba una caminata corta después de merendar.",
                    "what_to_watch": "Compara los días con y sin caminata.",
                ],
            ],
            "caveats": ["La cobertura fue del 96 %.", "Esto es una guía informativa y no consejo médico."],
            "questions_to_explore": ["¿Qué comiste los días con la subida más alta?"],
        ]
    }

    static func replyText(_ object: [String: Any]? = nil) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object ?? replyObject(), options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    /// Respuesta HTTP 200 del proveedor con `text` (un JSON) en el formato propio de cada API.
    static func reply(for provider: LLMProviderID, text: String, truncated: Bool = false) -> FixtureTransport.Reply {
        var object: [String: Any]
        switch provider {
        case .anthropic:
            let input = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            let block: [String: Any] = input.map { ["type": "tool_use", "id": "toolu_1", "name": ReportAnalysisPrompt.toolName, "input": $0] }
                ?? ["type": "text", "text": text]
            object = ["id": "msg_fixture", "type": "message", "role": "assistant", "content": [block],
                      "stop_reason": truncated ? "max_tokens" : (input == nil ? "end_turn" : "tool_use")]
        case .gemini:
            object = ["candidates": [["content": ["parts": [["text": text]]], "finishReason": truncated ? "MAX_TOKENS" : "STOP"]]]
        case .openai, .grok, .openrouter, .deepseek:
            object = ["choices": [["message": ["role": "assistant", "content": text], "finish_reason": truncated ? "length" : "stop"]]]
        }
        return FixtureTransport.Reply(status: 200, body: try! JSONSerialization.data(withJSONObject: object))
    }

    struct Environment {
        let service: ReportAnalysisService
        let transport: FixtureTransport
        let store: SQLiteStore
    }

    @MainActor
    static func makeService(provider: LLMProviderID = .anthropic, configured: Bool = true,
                            replies: [FixtureTransport.Reply] = [], model: LLMModel? = nil) async throws -> Environment {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        let keys = LLMKeyStore(itemFor: { items[$0]! })
        let settings = LLMSettingsStore(defaults: UserDefaults(suiteName: "report-analysis-tests-\(UUID().uuidString)")!)
        if configured {
            try await keys.save(LLMFixtures.testKey, for: provider)
            settings.setSelectedProvider(provider)
            settings.setSelectedModel(model ?? LLMFixtures.model(for: provider))
        }
        let path = FileManager.default.temporaryDirectory.appending(path: "t27d-\(UUID().uuidString).sqlite").path(percentEncoded: false)
        let store = try SQLiteStore(path: path)
        let transport = FixtureTransport(replies)
        let counter = IDCounter()
        let service = ReportAnalysisService(
            keys: keys, settings: settings, store: store,
            client: ReportAnalysisClient(transport: transport, log: RecordingLLMLogSink()), locale: "es-CO",
            now: { Date(timeIntervalSince1970: 1_800_000_100) }, makeID: { counter.next() })
        return Environment(service: service, transport: transport, store: store)
    }
}

/// Identificadores de análisis predecibles para las pruebas.
final class IDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> String { lock.withLock { value += 1; return "analysis-\(value)" } }
}
