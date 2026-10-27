import Foundation

/// Datos **conocidos** de precio e imágenes por modelo, con su fuente y fecha. Lo que no esté aquí ni
/// venga del catálogo del proveedor queda `pricing nil` ("No publicado") e `imageSupport
/// .unconfirmed` ("No confirmado"). No se inventa nada.
enum LLMCatalog {
    struct Entry: Sendable, Hashable {
        var imageSupport: ImageSupport
        var pricing: ModelPricing?
    }

    static let asOf = "2026-10"
    static let anthropicSource = "skill claude-api (tabla de precios de Anthropic)"
    static let xaiSource = "https://docs.x.ai/docs/models"
    static let openRouterSource = "catálogo de OpenRouter (/api/v1/models)"
    static let defaultAnthropicModel = "claude-haiku-5-5"

    private static func anthropic(_ input: Double, _ output: Double) -> Entry {
        // La lectura de imágenes la confirma `capabilities.image_input` de `GET /v1/models`.
        Entry(imageSupport: .unconfirmed,
              pricing: ModelPricing(inputUSDPerMTok: input, outputUSDPerMTok: output, source: anthropicSource, asOf: asOf))
    }

    private static func xai(_ input: Double, _ output: Double, image: ImageSupport = .unconfirmed) -> Entry {
        // Precio para prompts de menos de 200k tokens (los análisis de LingoScan siempre lo son).
        Entry(imageSupport: image,
              pricing: ModelPricing(inputUSDPerMTok: input, outputUSDPerMTok: output, source: xaiSource, asOf: asOf))
    }

    static let table: [LLMProviderID: [String: Entry]] = [
        .anthropic: [
            "claude-fable-5-1": anthropic(10, 50),
            "claude-fable-5": anthropic(10, 50),
            "claude-opus-5-5": anthropic(4, 20),
            "claude-opus-5": anthropic(5, 25),
            "claude-opus-4-8": anthropic(5, 25),
            "claude-opus-4-7": anthropic(5, 25),
            "claude-opus-4-6": anthropic(5, 25),
            "claude-sonnet-5-5": anthropic(2, 10),
            "claude-sonnet-5": anthropic(2, 10),
            "claude-sonnet-4-6": anthropic(3, 15),
            // Precio con prompts de hasta 100k tokens.
            "claude-haiku-5-5": anthropic(0.10, 0.50),
            "claude-haiku-4-5": anthropic(1, 5),
        ],
        .grok: [
            // docs.x.ai/docs/guides/image-understanding usa grok-4.7 con imágenes.
            "grok-4.7": xai(2, 6, image: .confirmed),
            "grok-4.6": xai(2, 6),
            "grok-4.5": xai(2, 6),
            "grok-4.3": xai(1.25, 2.50),
            "grok-4.20-0309-reasoning": xai(1.25, 2.50),
            "grok-4.20-0309-non-reasoning": xai(1.25, 2.50),
            "grok-4.20-multi-agent-0309": xai(1.25, 2.50),
            "grok-build-0.1": xai(1, 2),
        ],
    ]

    static func entry(provider: LLMProviderID, modelID: String) -> Entry? {
        table[provider]?[modelID]
    }

    /// Recomienda un solo modelo por catálogo: con imágenes confirmadas y precio conocido, el preferido
    /// del proveedor si está (Claude Haiku 5.5) o el más barato. Sin imágenes → no recomendado.
    static func applyRecommendations(_ models: [LLMModel]) -> [LLMModel] {
        let candidates = models.filter { model in
            model.imageSupport == .confirmed && model.pricing?.inputUSDPerMTok != nil && model.pricing?.outputUSDPerMTok != nil
        }
        let chosen = candidates.first { $0.provider == .anthropic && $0.id == defaultAnthropicModel }
            ?? candidates.min { totalPrice($0) < totalPrice($1) || (totalPrice($0) == totalPrice($1) && $0.id < $1.id) }
        return models.map { model in
            var model = model
            if model.id == chosen?.id, let pricing = model.pricing {
                model.recommendation = .recommended(reason: reason(for: model, pricing: pricing))
            } else if model.imageSupport == .none {
                model.recommendation = .notRecommended(reason: String(localized: "No acepta imágenes: solo sirve para describir la comida con texto."))
            } else {
                model.recommendation = .unknown
            }
            return model
        }
    }

    private static func totalPrice(_ model: LLMModel) -> Double {
        (model.pricing?.inputUSDPerMTok ?? .infinity) + (model.pricing?.outputUSDPerMTok ?? .infinity)
    }

    private static func reason(for model: LLMModel, pricing: ModelPricing) -> String {
        let input = (pricing.inputUSDPerMTok ?? 0).formatted(.number.precision(.fractionLength(2...4)))
        let output = (pricing.outputUSDPerMTok ?? 0).formatted(.number.precision(.fractionLength(2...4)))
        if model.provider == .anthropic && model.id == defaultAnthropicModel {
            return String(localized: "Recomendado por defecto: lee imágenes (confirmado), devuelve la respuesta estructurada y es el Claude más económico (\(input) $ entrada / \(output) $ salida por millón de tokens).")
        }
        return String(localized: "Lee imágenes (confirmado) y es el más económico con precio publicado (\(input) $ entrada / \(output) $ salida por millón de tokens).")
    }
}
