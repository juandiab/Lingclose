/// Un modelo del catálogo autenticado de un proveedor, enriquecido con `LLMCatalog`.
struct LLMModel: Identifiable, Sendable, Hashable, Codable {
    var id: String
    var provider: LLMProviderID
    var displayName: String
    var imageSupport: ImageSupport
    /// `nil` → "No publicado".
    var pricing: ModelPricing?
    var recommendation: ModelRecommendation
    var maxOutputTokens: Int?
    var supportsReasoningControl: Bool

    init(id: String, provider: LLMProviderID, displayName: String, imageSupport: ImageSupport = .unconfirmed,
         pricing: ModelPricing? = nil, recommendation: ModelRecommendation = .unknown,
         maxOutputTokens: Int? = nil, supportsReasoningControl: Bool = false) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.imageSupport = imageSupport
        self.pricing = pricing
        self.recommendation = recommendation
        self.maxOutputTokens = maxOutputTokens
        self.supportsReasoningControl = supportsReasoningControl
    }
}
