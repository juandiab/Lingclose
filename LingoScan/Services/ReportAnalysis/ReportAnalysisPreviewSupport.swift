import Foundation
import LingoCore

/// Llavero en memoria para previsualizaciones.
final class PreviewSecretItem: SecretItemStoring, @unchecked Sendable {
    func read() throws -> Data? { nil }
    func save(_ data: Data) throws {}
    func delete() throws {}
}

/// Almacén de análisis vacío para previsualizaciones: no guarda nada.
struct PreviewReportAnalysisStore: ReportAnalysisStoring {
    func insertReportAnalysis(_ record: ReportAnalysisRecord) async throws {}
    func recentReportAnalyses(limit: Int) async throws -> [ReportAnalysisRecord] { [] }
    func deleteReportAnalysis(id: String) async throws -> Bool { false }
}
