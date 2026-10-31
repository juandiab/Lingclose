import Foundation

/// Análisis por IA de reportes (T-27a, tabla `report_analyses` de la migración v4). Local: no se exporta.
extension SQLiteStore {
    /// Inserta un análisis. Falla si el `id` ya existe.
    public func insertReportAnalysis(_ record: ReportAnalysisRecord) throws {
        try connection.transaction {
            try connection.run("""
                INSERT INTO report_analyses (id, created_at_epoch_s, period_start_epoch_s, period_end_epoch_s, provider,
                  model, request_sha256, response_json, status, error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    SQLiteValue(record.id), SQLiteValue(record.createdAt.epochSeconds),
                    SQLiteValue(record.periodStart.epochSeconds), SQLiteValue(record.periodEnd.epochSeconds),
                    SQLiteValue(record.provider), SQLiteValue(record.model), SQLiteValue(record.requestSHA256),
                    SQLiteValue(record.responseJSON), SQLiteValue(record.status.rawValue), SQLiteValue(record.error),
                ])
        }
    }

    /// Análisis de exactamente ese período, del más reciente al más antiguo.
    public func reportAnalyses(periodStart: UTCInstant, periodEnd: UTCInstant) throws -> [ReportAnalysisRecord] {
        try connection.query("""
            SELECT id, created_at_epoch_s, period_start_epoch_s, period_end_epoch_s, provider, model, request_sha256,
              response_json, status, error
            FROM report_analyses WHERE period_start_epoch_s = ? AND period_end_epoch_s = ?
            ORDER BY created_at_epoch_s DESC, id DESC
            """, [SQLiteValue(periodStart.epochSeconds), SQLiteValue(periodEnd.epochSeconds)]) { try decodeReportAnalysis($0) }
    }

    /// Análisis cuyo período se solapa con `[from, to)`, del más reciente al más antiguo.
    public func reportAnalyses(overlapping from: UTCInstant, _ to: UTCInstant) throws -> [ReportAnalysisRecord] {
        try connection.query("""
            SELECT id, created_at_epoch_s, period_start_epoch_s, period_end_epoch_s, provider, model, request_sha256,
              response_json, status, error
            FROM report_analyses WHERE period_start_epoch_s < ? AND period_end_epoch_s > ?
            ORDER BY created_at_epoch_s DESC, id DESC
            """, [SQLiteValue(to.epochSeconds), SQLiteValue(from.epochSeconds)]) { try decodeReportAnalysis($0) }
    }

    /// Los `limit` análisis más recientes de cualquier período.
    public func recentReportAnalyses(limit: Int = 50) throws -> [ReportAnalysisRecord] {
        try connection.query("""
            SELECT id, created_at_epoch_s, period_start_epoch_s, period_end_epoch_s, provider, model, request_sha256,
              response_json, status, error
            FROM report_analyses ORDER BY created_at_epoch_s DESC, id DESC LIMIT ?
            """, [SQLiteValue(max(0, limit))]) { try decodeReportAnalysis($0) }
    }

    /// Borra un análisis. Devuelve `true` si existía.
    @discardableResult
    public func deleteReportAnalysis(id: String) throws -> Bool {
        try connection.transaction {
            let existed = try connection.queryFirst("SELECT 1 FROM report_analyses WHERE id = ?", [SQLiteValue(id)]) {
                $0.int(0)
            } != nil
            try connection.run("DELETE FROM report_analyses WHERE id = ?", [SQLiteValue(id)])
            return existed
        }
    }

    private func decodeReportAnalysis(_ s: SQLiteStatement) throws -> ReportAnalysisRecord {
        func required<T>(_ v: T?, _ column: String) throws -> T {
            guard let v else { throw StoreError.corruptRow(table: "report_analyses", detail: column) }
            return v
        }
        return ReportAnalysisRecord(
            id: try required(s.text(0), "id"),
            createdAt: UTCInstant(epochSeconds: try required(s.int64(1), "created_at_epoch_s")),
            periodStart: UTCInstant(epochSeconds: try required(s.int64(2), "period_start_epoch_s")),
            periodEnd: UTCInstant(epochSeconds: try required(s.int64(3), "period_end_epoch_s")),
            provider: try required(s.text(4), "provider"),
            model: try required(s.text(5), "model"),
            requestSHA256: try required(s.text(6), "request_sha256"),
            responseJSON: s.text(7),
            status: try required(s.text(8).flatMap(ReportAnalysisStatus.init(rawValue:)), "status"),
            error: s.text(9))
    }
}
