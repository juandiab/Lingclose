import Foundation
import LingoCore
import os
@testable import LingoScan

/// Proveedor falso: devuelve un `FoodAnalysis` fijo o un `LLMError`, y anota cada llamada.
final class FakeLLMProvider: LLMProvider, @unchecked Sendable {
    struct AnalyzeCall: Sendable {
        let request: FoodAnalysisRequest
        let model: LLMModel
        let apiKey: String
    }

    let id: LLMProviderID
    var analysis: FoodAnalysis
    var analyzeError: LLMError?
    var catalog: [LLMModel]
    var listError: LLMError?
    var rangeReply = LLMRangeReply(low: 75, high: 145, explanation: "Rango de prueba")
    var rangeError: LLMError?
    var delay: Duration?
    /// Espera antes de devolver el catálogo (para observar el paso `comprobando`).
    var listDelay: Duration?

    private let state = OSAllocatedUnfairLock(initialState: (analyze: [AnalyzeCall](), list: [String](), range: [RangeSuggestionRequest]()))

    init(id: LLMProviderID = .anthropic, analysis: FoodAnalysis = FakeLLMProvider.arepa,
         analyzeError: LLMError? = nil, catalog: [LLMModel] = [], listError: LLMError? = nil) {
        self.id = id
        self.analysis = analysis
        self.analyzeError = analyzeError
        self.catalog = catalog
        self.listError = listError
    }

    var analyzeCalls: [AnalyzeCall] { state.withLock { $0.analyze } }
    var listCalls: [String] { state.withLock { $0.list } }
    var rangeCalls: [RangeSuggestionRequest] { state.withLock { $0.range } }

    func listModels(apiKey: String) async throws -> [LLMModel] {
        state.withLock { $0.list.append(apiKey) }
        if let listDelay { try await Task.sleep(for: listDelay) }
        if let listError { throw listError }
        return catalog
    }

    func analyze(_ request: FoodAnalysisRequest, model: LLMModel, apiKey: String) async throws -> FoodAnalysis {
        state.withLock { $0.analyze.append(AnalyzeCall(request: request, model: model, apiKey: apiKey)) }
        if let delay { try await Task.sleep(for: delay) }
        if let analyzeError { throw analyzeError }
        return analysis
    }

    func suggestRange(_ request: RangeSuggestionRequest, model: LLMModel, apiKey: String) async throws -> LLMRangeReply {
        state.withLock { $0.range.append(request) }
        if let rangeError { throw rangeError }
        return rangeReply
    }

    /// T-25: el falso no sabe aconsejar; las pruebas del asistente usan `FixtureTransport`.
    func coach(_ request: CoachingRequest, model: LLMModel, apiKey: String) async throws -> LLMCoachingReply {
        throw LLMError.invalidResponse("FakeLLMProvider.coach")
    }

    /// 200 kcal / 30 g de carbohidratos por porción estimada.
    static let arepa = FoodAnalysis(
        kind: .food, name: "Arepa con queso",
        basis: .estimatedServing(description: "1 arepa mediana", grams: 120),
        baseNutrients: Nutrients(kcal: 200, carbsG: 30, proteinG: 6, fatG: 7),
        confidence: 0.7, assumptions: "Con queso campesino")
}
