/// Lo que se enviará, calculado antes de pedir nada (estado inicial de la hoja): tamaño (con el contexto opcional),
/// días, coste estimado y qué bloques encendidos quedaron vacíos (T-33).
struct ReportAnalysisPreview: Sendable, Equatable {
    var payloadBytes: Int
    /// Bytes del bloque de contexto opcional (0 con todo apagado).
    var contextBytes: Int
    var periodDays: Int
    var topicsWithData: Int
    var estimate: ReportAnalysisCostEstimate
    var sharing: ReportAnalysisSharing
    /// Interruptores encendidos sin nada que enviar en este período (Salud vacía, comidas sin nombre).
    var gaps: [ReportAnalysisContextGap]

    init(request: ReportAnalysisRequest, model: LLMModel, sharing: ReportAnalysisSharing = .none) {
        payloadBytes = request.payloadBytes
        contextBytes = request.contextBytes
        periodDays = request.periodDays
        topicsWithData = request.topicsWithData.count
        estimate = ReportAnalysisCostEstimate(request: request, model: model)
        self.sharing = sharing
        gaps = ReportAnalysisContext.gaps(in: request.context, sharing: sharing)
    }
}
