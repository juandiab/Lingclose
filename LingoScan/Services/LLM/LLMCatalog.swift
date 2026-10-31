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
    static let openAIPricingSource = "https://developers.openai.com/api/docs/pricing"
    static let openAIModelPageSource = "https://developers.openai.com/api/docs/models/<id> (\"Input modalities: text, image\")"
    static let geminiPricingSource = "https://ai.google.dev/gemini-api/docs/pricing"
    static let geminiImageSource = "https://ai.google.dev/gemini-api/docs/image-understanding (\"All Gemini model versions are multimodal\")"
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

    /// Precio de la página de precios de OpenAI (tarifa estándar, contexto corto). Imágenes confirmadas solo
    /// en los modelos cuya página dice "Input modalities: text, image" (comprobado el 2026-10-27).
    private static func openai(_ input: Double, _ output: Double, image: ImageSupport = .unconfirmed) -> Entry {
        Entry(imageSupport: image,
              pricing: ModelPricing(inputUSDPerMTok: input, outputUSDPerMTok: output, source: openAIPricingSource, asOf: asOf))
    }

    /// Precio de la página de precios de Gemini (nivel de pago, texto/imagen). Imágenes: la guía oficial de
    /// comprensión de imágenes afirma que todas las versiones de Gemini son multimodales (2026-10-27).
    private static func gemini(_ input: Double, _ output: Double) -> Entry {
        Entry(imageSupport: .confirmed,
              pricing: ModelPricing(inputUSDPerMTok: input, outputUSDPerMTok: output, source: geminiPricingSource, asOf: asOf))
    }

    static let table: [LLMProviderID: [String: Entry]] = [
        .openai: [
            // Página del modelo: "Input modalities: text, image".
            "gpt-6-luna": openai(0.10, 0.50, image: .confirmed),
            "gpt-5-mini": openai(0.25, 2.00, image: .confirmed),
            "gpt-4.1-mini": openai(0.40, 1.60, image: .confirmed),
            // Solo precio publicado; imágenes sin confirmar en su página.
            "gpt-5-nano": openai(0.05, 0.40),
            "gpt-4.1-nano": openai(0.10, 0.40),
            "gpt-4o-mini": openai(0.15, 0.60),
            "gpt-5.6-luna": openai(0.20, 1.20),
            "gpt-5.4-nano": openai(0.20, 1.25),
            "gpt-5.4-mini": openai(0.75, 4.50),
            "gpt-5": openai(1.25, 10),
            "gpt-5.1": openai(1.25, 10),
            "gpt-4.1": openai(2, 8),
            "gpt-4o": openai(2.50, 10),
        ],
        .gemini: [
            "gemini-2.5-flash-lite": gemini(0.10, 0.40),
            "gemini-2.5-flash": gemini(0.30, 2.50),
            "gemini-3.5-flash-lite": gemini(0.30, 2.50),
            "gemini-3-flash-preview": gemini(0.50, 3.00),
            // Precio vigente hasta el 2026-12-31 (sube a 1,50 / 7,50 desde 2027-01-01).
            "gemini-3.8-flash": gemini(0.75, 3.75),
            "gemini-3.6-flash": gemini(0.75, 3.75),
            "gemini-2.5-pro": gemini(1.25, 10),
            "gemini-3.1-pro-preview": gemini(2, 12),
        ],
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
                model.recommendation = .notRecommended(reason: String(localized: "llm.catalog.noImages", defaultValue: "No acepta imágenes: solo sirve para describir la comida con texto."))
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
            return String(
                localized: "llm.catalog.recommendedDefault",
                defaultValue: "Recomendado por defecto: lee imágenes (confirmado), devuelve la respuesta estructurada y es el Claude más económico (\(input) $ entrada / \(output) $ salida por millón de tokens)."
            )
        }
        return String(
            localized: "llm.catalog.cheapest",
            defaultValue: "Lee imágenes (confirmado) y es el más económico con precio publicado (\(input) $ entrada / \(output) $ salida por millón de tokens)."
        )
    }
}
