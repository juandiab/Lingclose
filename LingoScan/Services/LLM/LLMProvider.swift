import LingoCore

/// Un proveedor de LLM. Cada llamada es una sola petición HTTP: sin reintentos automáticos.
protocol LLMProvider: Sendable {
    var id: LLMProviderID { get }
    /// Catálogo autenticado. Que responda prueba que la clave tiene acceso, no que haya saldo.
    func listModels(apiKey: String) async throws -> [LLMModel]
    /// Analiza foto y/o descripción. Con imagen exige `model.imageSupport == .confirmed`.
    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis
    /// Propone un rango de referencia a partir de cifras agregadas (`RangeSuggestionRequest`). Solo texto;
    /// la respuesta se valida con `RangeSuggestionReplyParser` y se rechaza si sale de los límites.
    func suggestRange(_ request: RangeSuggestionRequest, model: LLMModel, apiKey: String) async throws -> LLMRangeReply
}
