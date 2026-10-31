/// Paso de migración: lleva la base de `version - 1` a `version`. Cada paso termina fijando
/// `PRAGMA user_version` dentro de su propio guion estático.
struct SchemaMigration: Sendable {
    let version: Int
    let apply: @Sendable (SQLiteConnection) throws -> Void
}

extension SchemaMigration {
    /// v4 (T-27a) = tabla `report_analyses`: análisis por IA de un período de reportes. Aditiva y local: no toca
    /// ninguna tabla existente ni entra en el `.lingoscan`.
    static let reportAnalyses = SchemaMigration(version: 4) { try $0.executeScript(v4) }

    static let v4: StaticString = """
    CREATE TABLE report_analyses (
      id                       TEXT PRIMARY KEY,
      created_at_epoch_s       INTEGER NOT NULL,
      period_start_epoch_s     INTEGER NOT NULL,
      period_end_epoch_s       INTEGER NOT NULL,
      provider                 TEXT NOT NULL,
      model                    TEXT NOT NULL,
      request_sha256           TEXT NOT NULL,
      response_json            TEXT,
      status                   TEXT NOT NULL,
      error                    TEXT
    );
    CREATE INDEX report_analyses_period ON report_analyses(period_start_epoch_s, period_end_epoch_s, created_at_epoch_s);

    PRAGMA user_version = 4;
    """
}
