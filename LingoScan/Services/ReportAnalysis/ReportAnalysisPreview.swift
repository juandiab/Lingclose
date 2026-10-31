/// Lo que se enviará, calculado antes de pedir nada (estado inicial de la hoja): tamaño, días y coste estimado.
struct ReportAnalysisPreview: Sendable, Equatable {
    var payloadBytes: Int
    var periodDays: Int
    var topicsWithData: Int
    var estimate: ReportAnalysisCostEstimate

    init(request: ReportAnalysisRequest, model: LLMModel) {
        payloadBytes = request.payloadBytes
        periodDays = request.periodDays
        topicsWithData = request.topicsWithData.count
        estimate = ReportAnalysisCostEstimate(request: request, model: model)
    }
}
