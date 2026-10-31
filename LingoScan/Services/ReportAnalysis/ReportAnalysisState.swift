/// Estado del análisis en pantalla (T-27d). `rejected` y `failed` llevan el motivo ya redactado.
enum ReportAnalysisState: Sendable, Equatable {
    case idle
    case loading
    case done(ReportAnalysisReply)
    case rejected(String)
    case failed(String)
}
