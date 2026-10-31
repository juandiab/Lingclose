import Foundation

/// Coste estimado de un análisis, para mostrarlo **antes** de enviar. Los tokens se estiman por tamaño (≈ 3 caracteres
/// por token en JSON denso); la salida se calcula con el tamaño esperado de una respuesta completa
/// (`ReportAnalysisPrompt.expectedOutputTokens`), no con el tope de la petición: es una estimación, no una factura.
/// Sin precio publicado del modelo, `usd` es `nil` y la interfaz dice "No publicado".
struct ReportAnalysisCostEstimate: Sendable, Equatable {
    static let charactersPerToken = 3.0

    var inputTokens: Int
    var outputTokens: Int
    var usd: Double?

    init(request: ReportAnalysisRequest, model: LLMModel) {
        let prompt = ReportAnalysisPrompt.prompt(for: request)
        let characters = Double(prompt.system.utf8.count + prompt.userText.utf8.count)
        inputTokens = Int((characters / Self.charactersPerToken).rounded(.up))
        outputTokens = ReportAnalysisPrompt.expectedOutputTokens
        if let pricing = model.pricing, let input = pricing.inputUSDPerMTok, let output = pricing.outputUSDPerMTok {
            usd = (Double(inputTokens) * input + Double(outputTokens) * output) / 1_000_000
        } else {
            usd = nil
        }
    }
}
