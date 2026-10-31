import LingoCore

/// Almacén de análisis (`report_analyses`). `SQLiteStore` lo cumple; las pruebas usan la misma base en un archivo temporal.
protocol ReportAnalysisStoring: Sendable {
    func insertReportAnalysis(_ record: ReportAnalysisRecord) async throws
    func recentReportAnalyses(limit: Int) async throws -> [ReportAnalysisRecord]
    @discardableResult func deleteReportAnalysis(id: String) async throws -> Bool
}

extension SQLiteStore: ReportAnalysisStoring {}
