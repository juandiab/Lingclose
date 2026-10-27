import Foundation
@testable import LingoScan

/// Respuestas grabadas en `LingoScanTests/Fixtures/LLM/`, cargadas por ruta relativa a `#filePath`
/// (como las de RoundWhiteDiscKit), y datos de prueba comunes. Ninguna clave es real.
enum LLMFixtures {
    static let testKey = "sk-test-NO-REAL"
    static let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0xFF, 0xD9])
    static let foodDescription = "arepa con queso del desayuno"

    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LLM/\(name).json")
    }

    static func data(_ name: String) -> Data {
        do {
            return try Data(contentsOf: url(name))
        } catch {
            fatalError("Falta la fixture \(name): \(error)")
        }
    }

    /// Modelo con visión confirmada (o `.none` para DeepSeek) para las pruebas de análisis.
    static func model(for provider: LLMProviderID, imageSupport: ImageSupport? = nil) -> LLMModel {
        let id = switch provider {
        case .anthropic: "claude-haiku-5-5"
        case .openai: "gpt-5-mini"
        case .grok: "grok-4.7"
        case .openrouter: "anthropic/claude-haiku-5-5"
        case .deepseek: "deepseek-flash"
        case .gemini: "gemini-3.6-flash"
        }
        let support = imageSupport ?? (provider == .deepseek ? .none : .confirmed)
        return LLMModel(id: id, provider: provider, displayName: id, imageSupport: support)
    }

    /// Petición con foto (si el proveedor lee imágenes) y descripción.
    static func request(for provider: LLMProviderID) -> FoodAnalysisRequest {
        FoodAnalysisRequest(imageJPEG: provider == .deepseek ? nil : fakeJPEG, description: foodDescription, locale: "es-CO")
    }

    static func provider(_ id: LLMProviderID, transport: FixtureTransport, log: RecordingLLMLogSink = RecordingLLMLogSink())
        -> any LLMProvider {
        LLMProviderRegistry(transport: transport, log: log).provider(for: id)
    }
}
