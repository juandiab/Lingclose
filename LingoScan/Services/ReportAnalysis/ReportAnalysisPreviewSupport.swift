import Foundation
import LingoCore

/// Llavero en memoria para previsualizaciones: vacío, o con una clave falsa (`-previewAnalysis YES`).
final class PreviewSecretItem: SecretItemStoring, @unchecked Sendable {
    private let value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func read() throws -> Data? { value.map { Data($0.utf8) } }
    func save(_ data: Data) throws {}
    func delete() throws {}
}

/// Almacén de análisis vacío para previsualizaciones: no guarda nada.
struct PreviewReportAnalysisStore: ReportAnalysisStoring {
    func insertReportAnalysis(_ record: ReportAnalysisRecord) async throws {}
    func recentReportAnalyses(limit: Int) async throws -> [ReportAnalysisRecord] { [] }
    func deleteReportAnalysis(id: String) async throws -> Bool { false }
}
