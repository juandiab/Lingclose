/// Esquema SQLite de LingoScan y migraciones ordenadas por `PRAGMA user_version`.
///
/// v1 = `DATOS_Y_HEALTHKIT.md` + columnas exigidas por `CONTRATO_V1.md` (draft.4). Las horas se
/// guardan como segundos Unix (`*_epoch_s`) para consultas por rango con índice; RFC 3339 solo en JSON.
enum StoreSchema {
    static let currentVersion = 1

    static let migrations: [SchemaMigration] = [
        SchemaMigration(version: 1) { try $0.executeScript(v1) },
    ]

    static func userVersion(_ c: SQLiteConnection) throws -> Int {
        try c.queryFirst("PRAGMA user_version") { $0.int(0) ?? 0 } ?? 0
    }

    /// Abre en WAL con claves foráneas y aplica en orden las migraciones pendientes, cada una en su transacción.
    static func prepare(_ c: SQLiteConnection) throws {
        try c.run("PRAGMA journal_mode = WAL")
        try c.run("PRAGMA foreign_keys = ON")
        try c.run("PRAGMA synchronous = NORMAL")
        let found = try userVersion(c)
        guard found <= currentVersion else {
            throw StoreError.schemaTooNew(found: found, supported: currentVersion)
        }
        for migration in migrations where migration.version > found {
            try c.transaction {
                try migration.apply(c)
                let reached = try userVersion(c)
                guard reached == migration.version else {
                    throw StoreError.migrationFailed(version: migration.version, reached: reached)
                }
            }
        }
    }

    static let v1: StaticString = """
    CREATE TABLE sensor_sessions (
      session_id               TEXT PRIMARY KEY,
      family                   TEXT NOT NULL,
      product_type             INTEGER NOT NULL,
      security_version         INTEGER NOT NULL,
      serial_redacted          TEXT,
      serial_hash              TEXT NOT NULL,
      firmware_hex             TEXT,
      warmup_minutes           INTEGER NOT NULL,
      wear_minutes             INTEGER NOT NULL,
      activation_time_epoch_s  INTEGER NOT NULL,
      activation_time_source   TEXT NOT NULL,
      activated_at_utc         TEXT NOT NULL,
      activated_by_app_id      TEXT NOT NULL,
      activation_source        TEXT NOT NULL,
      activation_state         TEXT NOT NULL,
      receiver_id_present      INTEGER NOT NULL,
      ended_at_epoch_s         INTEGER,
      end_reason               TEXT,
      last_life_count          INTEGER,
      aliases_json             TEXT NOT NULL DEFAULT '[]',
      synthetic                INTEGER NOT NULL,
      revision                 INTEGER NOT NULL DEFAULT 1,
      imported_from_app_id     TEXT,
      imported_from_archive_id TEXT
    );
    CREATE INDEX sensor_sessions_serial ON sensor_sessions(serial_hash);

    CREATE TABLE readings (
      record_id                TEXT PRIMARY KEY,
      source_record_id         TEXT,
      session_id               TEXT NOT NULL REFERENCES sensor_sessions(session_id),
      life_count               INTEGER NOT NULL,
      analyte                  TEXT NOT NULL,
      unit                     TEXT NOT NULL,
      measured_at_epoch_s      INTEGER NOT NULL,
      received_at_epoch_s      INTEGER NOT NULL,
      tz_at_capture            TEXT NOT NULL,
      origin                   TEXT NOT NULL,
      value_mgdl               INTEGER,
      capped_mgdl              INTEGER,
      uncapped_mgdl            INTEGER,
      historic_capped_mgdl     INTEGER,
      historic_uncapped_mgdl   INTEGER,
      historic_life_count      INTEGER,
      rate_centi               INTEGER,
      trend                    INTEGER,
      actionable               INTEGER,
      temperature_centi        INTEGER,
      range_bits               INTEGER,
      quality_flag             INTEGER NOT NULL,
      channel                  INTEGER,
      reserved_hex             TEXT,
      eligible                 INTEGER NOT NULL,
      exclusion_reason         TEXT,
      policy_id                TEXT NOT NULL,
      policy_version           TEXT NOT NULL,
      decoder_id               TEXT NOT NULL,
      decoder_version          TEXT NOT NULL,
      synthetic                INTEGER NOT NULL,
      deleted                  INTEGER NOT NULL DEFAULT 0,
      revision                 INTEGER NOT NULL DEFAULT 1,
      imported_from_app_id     TEXT,
      imported_from_archive_id TEXT,
      raw_hex                  TEXT,
      CHECK ((eligible = 1) = (exclusion_reason IS NULL))
    );
    CREATE INDEX readings_time ON readings(measured_at_epoch_s);
    CREATE INDEX readings_session_lc ON readings(session_id, life_count);

    CREATE TABLE events (
      event_id                 TEXT PRIMARY KEY,
      kind                     TEXT NOT NULL,
      at_epoch_s               INTEGER NOT NULL,
      tz                       TEXT NOT NULL,
      duration_min             INTEGER,
      carbs_g                  REAL,
      text                     TEXT,
      created_at_epoch_s       INTEGER NOT NULL,
      updated_at_epoch_s       INTEGER NOT NULL,
      revision                 INTEGER NOT NULL DEFAULT 1,
      edit_id                  TEXT NOT NULL,
      parent_edit_id           TEXT,
      edited_by_app_id         TEXT NOT NULL,
      deleted                  INTEGER NOT NULL DEFAULT 0,
      synthetic                INTEGER NOT NULL,
      imported_from_app_id     TEXT,
      imported_from_archive_id TEXT
    );
    CREATE INDEX events_time ON events(at_epoch_s);

    CREATE TABLE edit_lineage (
      edit_id                  TEXT PRIMARY KEY,
      parent_edit_id           TEXT,
      event_id                 TEXT NOT NULL
    );

    CREATE TABLE health_export_ledger (
      seq                      INTEGER PRIMARY KEY AUTOINCREMENT,
      attempt_id               TEXT NOT NULL UNIQUE,
      subject_id               TEXT NOT NULL,
      subject_kind             TEXT NOT NULL,
      writer_app_id            TEXT NOT NULL,
      sync_identifier          TEXT NOT NULL,
      sync_version             INTEGER NOT NULL,
      exported_at_epoch_s      INTEGER NOT NULL,
      result                   TEXT NOT NULL
    );
    CREATE INDEX ledger_subject ON health_export_ledger(subject_id, writer_app_id);

    CREATE TABLE conflicts (
      id                       INTEGER PRIMARY KEY AUTOINCREMENT,
      at_epoch_s               INTEGER NOT NULL,
      kind                     TEXT NOT NULL,
      subject_id               TEXT NOT NULL,
      resolution               TEXT NOT NULL,
      local_json               TEXT,
      remote_json              TEXT,
      remote_archive_id        TEXT
    );
    CREATE INDEX conflicts_subject ON conflicts(subject_id);

    CREATE TABLE archives (
      archive_id               TEXT PRIMARY KEY,
      created_at_epoch_s       INTEGER NOT NULL,
      path                     TEXT NOT NULL,
      readings                 INTEGER NOT NULL,
      manifest_sha256          TEXT NOT NULL,
      verified                 INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE imported_archives (
      archive_id               TEXT PRIMARY KEY,
      producer_app_id          TEXT NOT NULL,
      created_at_epoch_s       INTEGER NOT NULL,
      imported_at_epoch_s      INTEGER NOT NULL,
      sessions                 INTEGER NOT NULL,
      readings                 INTEGER NOT NULL,
      events                   INTEGER NOT NULL,
      ledger_entries           INTEGER NOT NULL,
      conflicts                INTEGER NOT NULL
    );

    CREATE TABLE event_log (
      id                       INTEGER PRIMARY KEY AUTOINCREMENT,
      at_epoch_s               INTEGER NOT NULL,
      level                    TEXT NOT NULL,
      category                 TEXT NOT NULL,
      message                  TEXT NOT NULL
    );

    PRAGMA user_version = 1;
    """
}
