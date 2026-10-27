import Foundation

/// Almacén operativo de LingoScan sobre SQLite (API C del sistema).
///
/// Todo el SQL es literal estático; los datos entran como parámetros ligados. Cada operación de
/// escritura corre en una transacción. Ver `docs/T-07.md` para las reglas de reconciliación.
public actor SQLiteStore {
    private let connection: SQLiteConnection
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    private let decoder = JSONDecoder()

    /// Abre (o crea) la base en `path`, activa WAL y claves foráneas y aplica las migraciones pendientes.
    public init(path: String, now: @escaping @Sendable () -> Date = { Date() }) throws {
        let c = try SQLiteConnection(path: path)
        try StoreSchema.prepare(c)
        self.connection = c
        self.now = now
    }

    public static var currentSchemaVersion: Int { StoreSchema.currentVersion }

    public func schemaVersion() throws -> Int { try StoreSchema.userVersion(connection) }

    public func journalMode() throws -> String {
        try connection.queryFirst("PRAGMA journal_mode") { $0.text(0) ?? "" } ?? ""
    }

    public func foreignKeysEnabled() throws -> Bool {
        try connection.queryFirst("PRAGMA foreign_keys") { $0.bool(0) ?? false } ?? false
    }

    /// Nombres de las tablas de usuario (para pruebas de esquema).
    public func tableNames() throws -> [String] {
        try connection.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
            $0.text(0) ?? ""
        }
    }

    private var nowInstant: UTCInstant { UTCInstant(now()) }

    // MARK: - Sesiones

    /// Inserta o reemplaza la fila de la sesión. Una sesión sintética nunca pasa a real (C6).
    public func upsertSession(_ s: SensorSessionRecord) throws {
        try connection.transaction {
            if let existing = try sessionLocked(s.sessionID), existing.synthetic, !s.synthetic {
                throw StoreError.syntheticSessionCannotBecomeReal(sessionID: s.sessionID)
            }
            let aliases = String(decoding: try encoder.encode(s.aliases), as: UTF8.self)
            try connection.run("""
                INSERT INTO sensor_sessions (session_id, family, product_type, security_version, serial_redacted,
                  serial_hash, firmware_hex, warmup_minutes, wear_minutes, activation_time_epoch_s,
                  activation_time_source, activated_at_utc, activated_by_app_id, activation_source, activation_state,
                  receiver_id_present, ended_at_epoch_s, end_reason, last_life_count, aliases_json, synthetic,
                  revision, imported_from_app_id, imported_from_archive_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                  family = excluded.family, product_type = excluded.product_type,
                  security_version = excluded.security_version, serial_redacted = excluded.serial_redacted,
                  serial_hash = excluded.serial_hash, firmware_hex = excluded.firmware_hex,
                  warmup_minutes = excluded.warmup_minutes, wear_minutes = excluded.wear_minutes,
                  activation_time_epoch_s = excluded.activation_time_epoch_s,
                  activation_time_source = excluded.activation_time_source,
                  activated_at_utc = excluded.activated_at_utc, activated_by_app_id = excluded.activated_by_app_id,
                  activation_source = excluded.activation_source, activation_state = excluded.activation_state,
                  receiver_id_present = excluded.receiver_id_present, ended_at_epoch_s = excluded.ended_at_epoch_s,
                  end_reason = excluded.end_reason, last_life_count = excluded.last_life_count,
                  aliases_json = excluded.aliases_json, synthetic = excluded.synthetic, revision = excluded.revision,
                  imported_from_app_id = excluded.imported_from_app_id,
                  imported_from_archive_id = excluded.imported_from_archive_id
                """, [
                    SQLiteValue(s.sessionID), SQLiteValue(s.sensorFamily.rawValue), SQLiteValue(s.productType),
                    SQLiteValue(s.securityVersion), SQLiteValue(s.sensorSerialRedacted), SQLiteValue(s.sensorSerialHash),
                    SQLiteValue(s.firmwareHex), SQLiteValue(s.warmupMinutes), SQLiteValue(s.wearMinutes),
                    SQLiteValue(s.activationTimeEpochS), SQLiteValue(s.activationTimeSource.rawValue),
                    SQLiteValue(s.activatedAt.rfc3339), SQLiteValue(s.activatedByAppID),
                    SQLiteValue(s.activationSource.rawValue), SQLiteValue(s.activationState.rawValue),
                    SQLiteValue(s.receiverIDPresent), SQLiteValue(s.endedAt?.epochSeconds),
                    SQLiteValue(s.endReason?.rawValue), SQLiteValue(s.lastLifeCount), SQLiteValue(aliases),
                    SQLiteValue(s.synthetic), SQLiteValue(s.revision), SQLiteValue(s.importedFrom?.appID),
                    SQLiteValue(s.importedFrom?.archiveID),
                ])
        }
    }

    public func session(byID id: String) throws -> SensorSessionRecord? {
        try sessionLocked(id)
    }

    /// Sesiones con el mismo `sensor_serial_hash` (identidad física, contrato §5.1).
    public func sessions(bySerialHash hash: String) throws -> [SensorSessionRecord] {
        try connection.query("""
            SELECT session_id, family, product_type, security_version, serial_redacted, serial_hash, firmware_hex,
              warmup_minutes, wear_minutes, activation_time_epoch_s, activation_time_source, activated_by_app_id,
              activation_source, activation_state, receiver_id_present, ended_at_epoch_s, end_reason, last_life_count,
              aliases_json, synthetic, revision, imported_from_app_id, imported_from_archive_id
            FROM sensor_sessions WHERE serial_hash = ? ORDER BY activation_time_epoch_s
            """, [SQLiteValue(hash)]) { try decodeSession($0) }
    }

    private func sessionLocked(_ id: String) throws -> SensorSessionRecord? {
        try connection.queryFirst("""
            SELECT session_id, family, product_type, security_version, serial_redacted, serial_hash, firmware_hex,
              warmup_minutes, wear_minutes, activation_time_epoch_s, activation_time_source, activated_by_app_id,
              activation_source, activation_state, receiver_id_present, ended_at_epoch_s, end_reason, last_life_count,
              aliases_json, synthetic, revision, imported_from_app_id, imported_from_archive_id
            FROM sensor_sessions WHERE session_id = ?
            """, [SQLiteValue(id)]) { try decodeSession($0) }
    }

    private func decodeSession(_ s: SQLiteStatement) throws -> SensorSessionRecord {
        func required<T>(_ v: T?, _ column: String) throws -> T {
            guard let v else { throw StoreError.corruptRow(table: "sensor_sessions", detail: column) }
            return v
        }
        let aliasesText = s.text(18) ?? "[]"
        let aliases = try decoder.decode([SessionAlias].self, from: Data(aliasesText.utf8))
        let importedFrom: ImportedFrom? = {
            guard let app = s.text(21), let archive = s.text(22) else { return nil }
            return ImportedFrom(appID: app, archiveID: archive)
        }()
        return SensorSessionRecord(
            sessionID: try required(s.text(0), "session_id"),
            sensorFamily: SensorFamily(rawValue: s.text(1) ?? "") ?? .unknown,
            productType: try required(s.int(2), "product_type"),
            securityVersion: try required(s.int(3), "security_version"),
            sensorSerialHash: try required(s.text(5), "serial_hash"),
            aliases: aliases,
            synthetic: try required(s.bool(19), "synthetic"),
            sensorSerialRedacted: s.text(4),
            firmwareHex: s.text(6),
            warmupMinutes: try required(s.int(7), "warmup_minutes"),
            wearMinutes: try required(s.int(8), "wear_minutes"),
            activationTimeEpochS: try required(s.int64(9), "activation_time_epoch_s"),
            activationTimeSource: try required(s.text(10).flatMap(ActivationTimeSource.init(rawValue:)), "activation_time_source"),
            activatedByAppID: try required(s.text(11), "activated_by_app_id"),
            activationSource: try required(s.text(12).flatMap(ActivationSource.init(rawValue:)), "activation_source"),
            activationState: try required(s.text(13).flatMap(ActivationState.init(rawValue:)), "activation_state"),
            receiverIDPresent: try required(s.bool(14), "receiver_id_present"),
            endedAt: s.int64(15).map(UTCInstant.init(epochSeconds:)),
            endReason: s.text(16).flatMap(SessionEndReason.init(rawValue:)),
            lastLifeCount: s.int(17),
            revision: try required(s.int(20), "revision"),
            importedFrom: importedFrom
        )
    }

    // MARK: - Lecturas

    /// Inserta una lectura de forma idempotente por `record_id`, con la precedencia de origen y la regla de
    /// levantar exclusiones del contrato §5.2. Rechaza una lectura real en una sesión sintética.
    @discardableResult
    public func insertReading(_ reading: GlucoseReading) throws -> ReadingInsertOutcome {
        try connection.transaction { try insertReadingLocked(reading) }
    }

    /// Varias lecturas en una sola transacción (todo o nada).
    @discardableResult
    public func insertReadings(_ readings: [GlucoseReading]) throws -> [ReadingInsertOutcome] {
        try connection.transaction { try readings.map { try insertReadingLocked($0) } }
    }

    /// Tombstone (contrato §5.2): conserva `record_id` y `raw`, `value = nil`, `excluded/deleted`, `revision + 1`.
    public func deleteReading(recordID: String) throws {
        try connection.transaction {
            guard var r = try readingLocked(recordID) else { throw StoreError.unknownReading(recordID: recordID) }
            guard !r.deleted else { return }
            r.deleted = true
            r.value = nil
            r.eligibility = .excluded(.deleted, policyID: r.eligibility.policyID, policyVersion: r.eligibility.policyVersion)
            r.revision += 1
            try writeReading(r)
        }
    }

    public func reading(recordID: String) throws -> GlucoseReading? {
        try readingLocked(recordID)
    }

    /// Lecturas con `measured_at` dentro del rango (ambos extremos incluidos), en orden de tiempo.
    public func readings(in range: ClosedRange<UTCInstant>, includeDeleted: Bool = false) throws -> [GlucoseReading] {
        try connection.query("""
            SELECT record_id, source_record_id, session_id, life_count, analyte, unit, measured_at_epoch_s,
              received_at_epoch_s, tz_at_capture, origin, value_mgdl, capped_mgdl, uncapped_mgdl, historic_capped_mgdl,
              historic_uncapped_mgdl, historic_life_count, rate_centi, trend, actionable, temperature_centi, range_bits,
              quality_flag, channel, reserved_hex, eligible, exclusion_reason, policy_id, policy_version, decoder_id,
              decoder_version, synthetic, deleted, revision, imported_from_app_id, imported_from_archive_id
            FROM readings
            WHERE measured_at_epoch_s BETWEEN ? AND ? AND (deleted = 0 OR ? = 1)
            ORDER BY measured_at_epoch_s, record_id
            """, [SQLiteValue(range.lowerBound.epochSeconds), SQLiteValue(range.upperBound.epochSeconds),
                  SQLiteValue(includeDeleted)]) { try decodeReading($0) }
    }

    /// Lecturas de una sesión por rango de `life_count` (ambos incluidos), en orden ascendente.
    public func readings(sessionID: String, lifeCountRange: ClosedRange<Int>, includeDeleted: Bool = false) throws -> [GlucoseReading] {
        try connection.query("""
            SELECT record_id, source_record_id, session_id, life_count, analyte, unit, measured_at_epoch_s,
              received_at_epoch_s, tz_at_capture, origin, value_mgdl, capped_mgdl, uncapped_mgdl, historic_capped_mgdl,
              historic_uncapped_mgdl, historic_life_count, rate_centi, trend, actionable, temperature_centi, range_bits,
              quality_flag, channel, reserved_hex, eligible, exclusion_reason, policy_id, policy_version, decoder_id,
              decoder_version, synthetic, deleted, revision, imported_from_app_id, imported_from_archive_id
            FROM readings
            WHERE session_id = ? AND life_count BETWEEN ? AND ? AND (deleted = 0 OR ? = 1)
            ORDER BY life_count, analyte
            """, [SQLiteValue(sessionID), SQLiteValue(lifeCountRange.lowerBound), SQLiteValue(lifeCountRange.upperBound),
                  SQLiteValue(includeDeleted)]) { try decodeReading($0) }
    }

    public func readingCount() throws -> Int {
        try connection.queryFirst("SELECT COUNT(*) FROM readings") { $0.int(0) ?? 0 } ?? 0
    }

    private func insertReadingLocked(_ incoming: GlucoseReading) throws -> ReadingInsertOutcome {
        guard RecordID.lifeCountRange.contains(incoming.lifeCount) else {
            throw StoreError.lifeCountOutOfRange(incoming.lifeCount)
        }
        let expected = RecordID.make(sessionID: incoming.sessionID, analyte: incoming.analyte, lifeCount: incoming.lifeCount)
        guard incoming.recordID == expected else {
            throw StoreError.recordIDMismatch(recordID: incoming.recordID, expected: expected)
        }
        guard let session = try sessionLocked(incoming.sessionID) else {
            throw StoreError.unknownSession(sessionID: incoming.sessionID)
        }
        // Criterio del ajuste de Astra: procedencia persistida, aunque el llamador diga "real".
        if session.synthetic && !incoming.synthetic {
            throw StoreError.realReadingInSyntheticSession(recordID: incoming.recordID, sessionID: session.sessionID)
        }
        if incoming.origin == .live,
           let lastLive = try connection.queryFirst(
               "SELECT MAX(life_count) FROM readings WHERE session_id = ? AND analyte = ? AND origin = 'live'",
               [SQLiteValue(incoming.sessionID), SQLiteValue(incoming.analyte.rawValue)], { $0.int(0) }) ?? nil,
           incoming.lifeCount < lastLive {
            try logLocked(.warning, category: "live_life_count_regression",
                          "live lc \(incoming.lifeCount) < último live \(lastLive)")
        }
        guard let existing = try readingLocked(incoming.recordID) else {
            try writeReading(incoming)
            return .inserted
        }
        return try reconcile(existing: existing, incoming: incoming)
    }

    /// Reglas del productor (contrato §5.2): un registro por `record_id`; precedencia de origen;
    /// levantar exclusión solo con `raw` de ruta distinta; nunca degradar una lectura elegible.
    private func reconcile(existing e: GlucoseReading, incoming n: GlucoseReading) throws -> ReadingInsertOutcome {
        // Tombstones pegajosos.
        if e.deleted { return .unchanged }
        // Sintético contra real: nunca se mezclan.
        if e.synthetic != n.synthetic {
            try conflictOnce(.reading, e.recordID, .keptLocal, local: e, remote: n, archive: n.importedFrom?.archiveID)
            return .keptExisting
        }
        if e.raw == n.raw {
            // Mismos bytes: a lo sumo sube el origen (no se atribuyen bytes de otra ruta).
            guard n.origin.precedence > e.origin.precedence else { return .unchanged }
            var upgraded = e
            upgraded.origin = n.origin
            upgraded.revision = e.revision + 1
            try writeReading(upgraded)
            return .originUpgraded
        }
        let distinctRoute = !e.raw.isEquivalent(to: n.raw) && e.origin != n.origin
        if distinctRoute, let reason = e.eligibility.reason, reason.isLiftableByAnotherRoute,
           n.eligibility.isEligible, !n.deleted {
            try replace(e, with: n)
            return .exclusionLifted
        }
        let wouldDowngrade = e.eligibility.isEligible && !n.eligibility.isEligible
        if n.origin.precedence > e.origin.precedence, !wouldDowngrade, !n.deleted {
            try replace(e, with: n)
            return .replaced
        }
        // Observación complementaria: se conserva con su origen en `conflicts`.
        try conflictOnce(.reading, e.recordID, .keptLocal, local: e, remote: n, archive: n.importedFrom?.archiveID)
        return .keptExisting
    }

    private func replace(_ old: GlucoseReading, with new: GlucoseReading) throws {
        var r = new
        r.revision = old.revision + 1
        try writeReading(r)
        try conflictOnce(.reading, old.recordID, .merged, local: old, remote: new, archive: new.importedFrom?.archiveID)
    }

    private func readingLocked(_ recordID: String) throws -> GlucoseReading? {
        try connection.queryFirst("""
            SELECT record_id, source_record_id, session_id, life_count, analyte, unit, measured_at_epoch_s,
              received_at_epoch_s, tz_at_capture, origin, value_mgdl, capped_mgdl, uncapped_mgdl, historic_capped_mgdl,
              historic_uncapped_mgdl, historic_life_count, rate_centi, trend, actionable, temperature_centi, range_bits,
              quality_flag, channel, reserved_hex, eligible, exclusion_reason, policy_id, policy_version, decoder_id,
              decoder_version, synthetic, deleted, revision, imported_from_app_id, imported_from_archive_id
            FROM readings WHERE record_id = ?
            """, [SQLiteValue(recordID)]) { try decodeReading($0) }
    }

    private func writeReading(_ r: GlucoseReading) throws {
        try connection.run("""
            INSERT INTO readings (record_id, source_record_id, session_id, life_count, analyte, unit,
              measured_at_epoch_s, received_at_epoch_s, tz_at_capture, origin, value_mgdl, capped_mgdl, uncapped_mgdl,
              historic_capped_mgdl, historic_uncapped_mgdl, historic_life_count, rate_centi, trend, actionable,
              temperature_centi, range_bits, quality_flag, channel, reserved_hex, eligible, exclusion_reason,
              policy_id, policy_version, decoder_id, decoder_version, synthetic, deleted, revision,
              imported_from_app_id, imported_from_archive_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(record_id) DO UPDATE SET
              source_record_id = excluded.source_record_id, measured_at_epoch_s = excluded.measured_at_epoch_s,
              received_at_epoch_s = excluded.received_at_epoch_s, tz_at_capture = excluded.tz_at_capture,
              origin = excluded.origin, value_mgdl = excluded.value_mgdl, capped_mgdl = excluded.capped_mgdl,
              uncapped_mgdl = excluded.uncapped_mgdl, historic_capped_mgdl = excluded.historic_capped_mgdl,
              historic_uncapped_mgdl = excluded.historic_uncapped_mgdl,
              historic_life_count = excluded.historic_life_count, rate_centi = excluded.rate_centi,
              trend = excluded.trend, actionable = excluded.actionable,
              temperature_centi = excluded.temperature_centi, range_bits = excluded.range_bits,
              quality_flag = excluded.quality_flag, channel = excluded.channel, reserved_hex = excluded.reserved_hex,
              eligible = excluded.eligible, exclusion_reason = excluded.exclusion_reason,
              policy_id = excluded.policy_id, policy_version = excluded.policy_version,
              decoder_id = excluded.decoder_id, decoder_version = excluded.decoder_version,
              synthetic = excluded.synthetic, deleted = excluded.deleted, revision = excluded.revision,
              imported_from_app_id = excluded.imported_from_app_id,
              imported_from_archive_id = excluded.imported_from_archive_id
            """, [
                SQLiteValue(r.recordID), SQLiteValue(r.sourceRecordID), SQLiteValue(r.sessionID),
                SQLiteValue(r.lifeCount), SQLiteValue(r.analyte.rawValue), SQLiteValue(r.unit),
                SQLiteValue(r.measuredAt.epochSeconds), SQLiteValue(r.receivedAt.epochSeconds),
                SQLiteValue(r.tzAtCapture), SQLiteValue(r.origin.rawValue), SQLiteValue(r.value),
                SQLiteValue(r.raw.capped), SQLiteValue(r.raw.uncapped), SQLiteValue(r.raw.historicCapped),
                SQLiteValue(r.raw.historicUncapped), SQLiteValue(r.raw.historicLifeCount),
                SQLiteValue(r.raw.rateCenti), SQLiteValue(r.raw.trend), SQLiteValue(r.raw.actionable),
                SQLiteValue(r.raw.temperatureCenti), SQLiteValue(r.raw.rangeBits), SQLiteValue(r.raw.qualityFlag),
                SQLiteValue(r.raw.channel), SQLiteValue(r.raw.reservedHex), SQLiteValue(r.eligibility.isEligible),
                SQLiteValue(r.eligibility.reason?.rawValue), SQLiteValue(r.eligibility.policyID),
                SQLiteValue(r.eligibility.policyVersion), SQLiteValue(r.decoder.id), SQLiteValue(r.decoder.version),
                SQLiteValue(r.synthetic), SQLiteValue(r.deleted), SQLiteValue(r.revision),
                SQLiteValue(r.importedFrom?.appID), SQLiteValue(r.importedFrom?.archiveID),
            ])
    }

    private func decodeReading(_ s: SQLiteStatement) throws -> GlucoseReading {
        func required<T>(_ v: T?, _ column: String) throws -> T {
            guard let v else { throw StoreError.corruptRow(table: "readings", detail: column) }
            return v
        }
        let raw = RawReading(
            capped: s.int(11), uncapped: s.int(12), historicCapped: s.int(13), historicUncapped: s.int(14),
            historicLifeCount: s.int(15), rateCenti: s.int(16), trend: s.int(17), actionable: s.bool(18),
            temperatureCenti: s.int(19), rangeBits: s.int(20), qualityFlag: try required(s.bool(21), "quality_flag"),
            channel: s.int(22), reservedHex: s.text(23)
        )
        let policyID = try required(s.text(26), "policy_id")
        let policyVersion = try required(s.text(27), "policy_version")
        let eligibility: Eligibility
        if try required(s.bool(24), "eligible") {
            eligibility = .eligible(policyID: policyID, policyVersion: policyVersion)
        } else {
            let reason = try required(s.text(25).flatMap(ExclusionReason.init(rawValue:)), "exclusion_reason")
            eligibility = .excluded(reason, policyID: policyID, policyVersion: policyVersion)
        }
        let importedFrom: ImportedFrom? = {
            guard let app = s.text(33), let archive = s.text(34) else { return nil }
            return ImportedFrom(appID: app, archiveID: archive)
        }()
        var reading = GlucoseReading(
            sessionID: try required(s.text(2), "session_id"),
            lifeCount: try required(s.int(3), "life_count"),
            analyte: try required(s.text(4).flatMap(Analyte.init(rawValue:)), "analyte"),
            unit: try required(s.text(5), "unit"),
            measuredAt: UTCInstant(epochSeconds: try required(s.int64(6), "measured_at_epoch_s")),
            receivedAt: UTCInstant(epochSeconds: try required(s.int64(7), "received_at_epoch_s")),
            tzAtCapture: try required(s.text(8), "tz_at_capture"),
            origin: try required(s.text(9).flatMap(ReadingOrigin.init(rawValue:)), "origin"),
            value: s.int(10),
            raw: raw,
            eligibility: eligibility,
            decoder: DecoderInfo(id: try required(s.text(28), "decoder_id"), version: try required(s.text(29), "decoder_version")),
            synthetic: try required(s.bool(30), "synthetic"),
            deleted: try required(s.bool(31), "deleted"),
            revision: try required(s.int(32), "revision"),
            importedFrom: importedFrom,
            sourceRecordID: s.text(1)
        )
        reading.recordID = try required(s.text(0), "record_id")
        return reading
    }

    // MARK: - Eventos del diario

    /// Guarda una versión de un evento aplicando el linaje de ediciones (contrato §5.3, C3).
    /// `ancestors` son los eslabones `edit_ancestors` que traiga un paquete; todos quedan en `edit_lineage`.
    @discardableResult
    public func upsertEvent(_ event: DiaryEvent, ancestors: [EditLink] = []) throws -> EventUpsertOutcome {
        try connection.transaction {
            for link in ancestors + [event.editLink] {
                try connection.run(
                    "INSERT OR IGNORE INTO edit_lineage (edit_id, parent_edit_id, event_id) VALUES (?, ?, ?)",
                    [SQLiteValue(link.editID), SQLiteValue(link.parentEditID), SQLiteValue(event.eventID)])
            }
            guard let local = try eventLocked(event.eventID) else {
                try writeEvent(event)
                return .inserted
            }
            if local.editID == event.editID { return .unchanged }
            let remoteChain = try lineage(startingAt: event.parentEditID)
            if remoteChain.ids.contains(local.editID) {
                try writeEvent(event)
                return .tookDescendant
            }
            let localChain = try lineage(startingAt: local.parentEditID)
            if localChain.ids.contains(event.editID) { return .keptNewerLocal }
            if remoteChain.complete && localChain.complete {
                try conflictOnce(.event, event.eventID, .divergent, local: local, remote: event,
                                 archive: event.importedFrom?.archiveID)
                return .divergent
            }
            try conflictOnce(.event, event.eventID, .lineageUnknown, local: local, remote: event,
                             archive: event.importedFrom?.archiveID)
            return .lineageUnknown
        }
    }

    public func event(id: String) throws -> DiaryEvent? { try eventLocked(id) }

    /// Resuelve un conflicto `divergent`/`lineage_unknown` con la elección del usuario (contrato §5.3):
    /// `choice` es una edición nueva cuyo `parent_edit_id` es la versión elegida, que debe ser la actual
    /// o una versión remota guardada en `conflicts` para este evento. Devuelve `false` si no lo es.
    @discardableResult
    public func resolveEventConflict(choice: DiaryEvent) throws -> Bool {
        try connection.transaction {
            guard let parent = choice.parentEditID, let local = try eventLocked(choice.eventID) else { return false }
            var candidates: Set<String> = [local.editID]
            for c in try conflicts(id: choice.eventID) where c.kind == .event
                && (c.resolution == .divergent || c.resolution == .lineageUnknown) {
                if let remote = try c.remote?.decoded(as: DiaryEvent.self) { candidates.insert(remote.editID) }
            }
            guard candidates.contains(parent) else { return false }
            try connection.run(
                "INSERT OR IGNORE INTO edit_lineage (edit_id, parent_edit_id, event_id) VALUES (?, ?, ?)",
                [SQLiteValue(choice.editID), SQLiteValue(parent), SQLiteValue(choice.eventID)])
            try writeEvent(choice)
            return true
        }
    }


    /// Eventos con `at` dentro del rango, incluidos los tombstones si se piden.
    public func events(in range: ClosedRange<UTCInstant>, includeDeleted: Bool = false) throws -> [DiaryEvent] {
        try connection.query("""
            SELECT event_id, kind, at_epoch_s, tz, duration_min, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
              revision, edit_id, parent_edit_id, edited_by_app_id, deleted, synthetic, imported_from_app_id,
              imported_from_archive_id
            FROM events WHERE at_epoch_s BETWEEN ? AND ? AND (deleted = 0 OR ? = 1) ORDER BY at_epoch_s
            """, [SQLiteValue(range.lowerBound.epochSeconds), SQLiteValue(range.upperBound.epochSeconds),
                  SQLiteValue(includeDeleted)]) { try decodeEvent($0) }
    }

    /// `edit_ancestors` de un evento: desde `parent_edit_id` hasta la creación. `nil` si falta un eslabón.
    public func editAncestors(of event: DiaryEvent) throws -> [EditLink]? {
        let chain = try lineage(startingAt: event.parentEditID)
        return chain.complete ? chain.links : nil
    }

    private func lineage(startingAt start: String?) throws -> (ids: Set<String>, links: [EditLink], complete: Bool) {
        var ids = Set<String>()
        var links: [EditLink] = []
        var current = start
        while let id = current {
            guard !ids.contains(id) else { return (ids, links, false) }  // ciclo
            let parent: String?? = try connection.queryFirst(
                "SELECT parent_edit_id FROM edit_lineage WHERE edit_id = ?", [SQLiteValue(id)]) { $0.text(0) }
            guard let parent else { return (ids, links, false) }  // eslabón ausente
            ids.insert(id)
            links.append(EditLink(editID: id, parentEditID: parent))
            current = parent
        }
        return (ids, links, true)
    }

    private func eventLocked(_ id: String) throws -> DiaryEvent? {
        try connection.queryFirst("""
            SELECT event_id, kind, at_epoch_s, tz, duration_min, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
              revision, edit_id, parent_edit_id, edited_by_app_id, deleted, synthetic, imported_from_app_id,
              imported_from_archive_id
            FROM events WHERE event_id = ?
            """, [SQLiteValue(id)]) { try decodeEvent($0) }
    }

    private func writeEvent(_ e: DiaryEvent) throws {
        try connection.run("""
            INSERT INTO events (event_id, kind, at_epoch_s, tz, duration_min, carbs_g, text, created_at_epoch_s,
              updated_at_epoch_s, revision, edit_id, parent_edit_id, edited_by_app_id, deleted, synthetic,
              imported_from_app_id, imported_from_archive_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
              kind = excluded.kind, at_epoch_s = excluded.at_epoch_s, tz = excluded.tz,
              duration_min = excluded.duration_min, carbs_g = excluded.carbs_g, text = excluded.text,
              created_at_epoch_s = excluded.created_at_epoch_s, updated_at_epoch_s = excluded.updated_at_epoch_s,
              revision = excluded.revision, edit_id = excluded.edit_id, parent_edit_id = excluded.parent_edit_id,
              edited_by_app_id = excluded.edited_by_app_id, deleted = excluded.deleted,
              synthetic = excluded.synthetic, imported_from_app_id = excluded.imported_from_app_id,
              imported_from_archive_id = excluded.imported_from_archive_id
            """, [
                SQLiteValue(e.eventID), SQLiteValue(e.kind.rawValue), SQLiteValue(e.at.epochSeconds), SQLiteValue(e.tz),
                SQLiteValue(e.durationMin), SQLiteValue(e.carbsG), SQLiteValue(e.text),
                SQLiteValue(e.createdAt.epochSeconds), SQLiteValue(e.updatedAt.epochSeconds), SQLiteValue(e.revision),
                SQLiteValue(e.editID), SQLiteValue(e.parentEditID), SQLiteValue(e.editedByAppID),
                SQLiteValue(e.deleted), SQLiteValue(e.synthetic), SQLiteValue(e.importedFrom?.appID),
                SQLiteValue(e.importedFrom?.archiveID),
            ])
    }

    private func decodeEvent(_ s: SQLiteStatement) throws -> DiaryEvent {
        func required<T>(_ v: T?, _ column: String) throws -> T {
            guard let v else { throw StoreError.corruptRow(table: "events", detail: column) }
            return v
        }
        let importedFrom: ImportedFrom? = {
            guard let app = s.text(15), let archive = s.text(16) else { return nil }
            return ImportedFrom(appID: app, archiveID: archive)
        }()
        return DiaryEvent(
            eventID: try required(s.text(0), "event_id"),
            kind: try required(s.text(1).flatMap(DiaryEventKind.init(rawValue:)), "kind"),
            at: UTCInstant(epochSeconds: try required(s.int64(2), "at_epoch_s")),
            tz: try required(s.text(3), "tz"),
            durationMin: s.int(4),
            carbsG: s.double(5),
            text: s.text(6),
            createdAt: UTCInstant(epochSeconds: try required(s.int64(7), "created_at_epoch_s")),
            updatedAt: UTCInstant(epochSeconds: try required(s.int64(8), "updated_at_epoch_s")),
            revision: try required(s.int(9), "revision"),
            editID: try required(s.text(10), "edit_id"),
            parentEditID: s.text(11),
            editedByAppID: try required(s.text(12), "edited_by_app_id"),
            deleted: try required(s.bool(13), "deleted"),
            synthetic: try required(s.bool(14), "synthetic"),
            importedFrom: importedFrom
        )
    }

    // MARK: - Ledger de Health (append-only)

    /// Añade un intento. Devuelve `false` si ese `attempt_id` ya estaba (unión por `attempt_id`, §8.4).
    @discardableResult
    public func appendLedger(_ entry: HealthLedgerEntry) throws -> Bool {
        try connection.transaction {
            try connection.run("""
                INSERT OR IGNORE INTO health_export_ledger (attempt_id, subject_id, subject_kind, writer_app_id,
                  sync_identifier, sync_version, exported_at_epoch_s, result)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    SQLiteValue(entry.attemptID), SQLiteValue(entry.subjectID), SQLiteValue(entry.subjectKind.rawValue),
                    SQLiteValue(entry.writerAppID), SQLiteValue(entry.syncIdentifier), SQLiteValue(entry.syncVersion),
                    SQLiteValue(entry.exportedAt.epochSeconds), SQLiteValue(entry.result.rawValue),
                ])
            return connection.changes == 1
        }
    }

    public func ledgerEntries(subjectID: String) throws -> [HealthLedgerEntry] {
        try connection.query("""
            SELECT attempt_id, subject_id, subject_kind, writer_app_id, sync_identifier, sync_version,
              exported_at_epoch_s, result
            FROM health_export_ledger WHERE subject_id = ? ORDER BY exported_at_epoch_s, seq
            """, [SQLiteValue(subjectID)]) { s in
            guard let attempt = s.text(0), let subject = s.text(1),
                  let kind = s.text(2).flatMap(HealthSubjectKind.init(rawValue:)), let writer = s.text(3),
                  let sync = s.text(4), let version = s.int(5), let at = s.int64(6),
                  let result = s.text(7).flatMap(HealthLedgerResult.init(rawValue:))
            else { throw StoreError.corruptRow(table: "health_export_ledger", detail: "fila incompleta") }
            return HealthLedgerEntry(attemptID: attempt, subjectID: subject, subjectKind: kind, writerAppID: writer,
                                     syncIdentifier: sync, syncVersion: version,
                                     exportedAt: UTCInstant(epochSeconds: at), result: result)
        }
    }

    /// Estado derivado (contrato §5.4, C4): `written` si hay un `written` con el `sync_version` más alto
    /// conocido (un fallo posterior no lo borra); si no, el resultado del último intento de esa versión.
    public func derivedHealthState(subjectID: String, writerAppID: String) throws -> DerivedHealthState {
        let attempts: [(version: Int, result: HealthLedgerResult)] = try connection.query("""
            SELECT sync_version, result FROM health_export_ledger
            WHERE subject_id = ? AND writer_app_id = ? ORDER BY exported_at_epoch_s, seq
            """, [SQLiteValue(subjectID), SQLiteValue(writerAppID)]) { s in
            guard let v = s.int(0), let r = s.text(1).flatMap(HealthLedgerResult.init(rawValue:)) else {
                throw StoreError.corruptRow(table: "health_export_ledger", detail: "sync_version/result")
            }
            return (v, r)
        }
        guard let maxVersion = attempts.map(\.version).max() else { return .none }
        let atMax = attempts.filter { $0.version == maxVersion }
        if atMax.contains(where: { $0.result == .written }) { return .written }
        return atMax.last?.result == .unknown ? .unknown : .failed
    }

    /// Huecos pendientes (§5.4): lecturas elegibles, no borradas, no sintéticas y de sesión no sintética,
    /// y comidas con carbohidratos, sin estado `written` para ninguna escritora. En orden de tiempo.
    public func pendingHealthSubjects() throws -> [PendingHealthSubject] {
        let readings: [PendingHealthSubject] = try connection.query("""
            SELECT r.record_id, r.measured_at_epoch_s FROM readings r
            JOIN sensor_sessions s ON s.session_id = r.session_id AND s.synthetic = 0
            WHERE r.eligible = 1 AND r.deleted = 0 AND r.synthetic = 0 AND r.value_mgdl IS NOT NULL
              AND NOT EXISTS (
                SELECT 1 FROM health_export_ledger l
                WHERE l.subject_id = r.record_id AND l.result = 'written'
                  AND l.sync_version = (SELECT MAX(l2.sync_version) FROM health_export_ledger l2
                                        WHERE l2.subject_id = l.subject_id AND l2.writer_app_id = l.writer_app_id))
            ORDER BY r.measured_at_epoch_s
            """) { s in
            PendingHealthSubject(subjectID: s.text(0) ?? "", subjectKind: .glucose,
                                 measuredAt: UTCInstant(epochSeconds: s.int64(1) ?? 0))
        }
        let carbs: [PendingHealthSubject] = try connection.query("""
            SELECT e.event_id, e.at_epoch_s FROM events e
            WHERE e.kind = 'meal' AND e.carbs_g IS NOT NULL AND e.deleted = 0 AND e.synthetic = 0
              AND NOT EXISTS (
                SELECT 1 FROM health_export_ledger l
                WHERE l.subject_id = e.event_id AND l.result = 'written'
                  AND l.sync_version = (SELECT MAX(l2.sync_version) FROM health_export_ledger l2
                                        WHERE l2.subject_id = l.subject_id AND l2.writer_app_id = l.writer_app_id))
            ORDER BY e.at_epoch_s
            """) { s in
            PendingHealthSubject(subjectID: s.text(0) ?? "", subjectKind: .carbs,
                                 measuredAt: UTCInstant(epochSeconds: s.int64(1) ?? 0))
        }
        return (readings + carbs).sorted { ($0.measuredAt, $0.subjectID) < ($1.measuredAt, $1.subjectID) }
    }

    // MARK: - Conflictos

    public func appendConflict(_ conflict: ConflictRecord) throws {
        try connection.transaction { try writeConflict(conflict) }
    }

    /// Conflictos de un `record_id`/`event_id`/`session_id`, o todos si `id == nil`, en orden de inserción.
    public func conflicts(id: String? = nil) throws -> [ConflictRecord] {
        try connection.query("""
            SELECT at_epoch_s, kind, subject_id, resolution, local_json, remote_json, remote_archive_id
            FROM conflicts WHERE (? IS NULL OR subject_id = ?) ORDER BY id
            """, [SQLiteValue(id), SQLiteValue(id)]) { s in
            guard let at = s.int64(0), let kind = s.text(1).flatMap(ConflictKind.init(rawValue:)),
                  let subject = s.text(2), let resolution = s.text(3).flatMap(ConflictResolution.init(rawValue:))
            else { throw StoreError.corruptRow(table: "conflicts", detail: "fila incompleta") }
            return ConflictRecord(
                at: UTCInstant(epochSeconds: at), kind: kind, id: subject, resolution: resolution,
                local: try s.text(4).map { try decoder.decode(JSONValue.self, from: Data($0.utf8)) },
                remote: try s.text(5).map { try decoder.decode(JSONValue.self, from: Data($0.utf8)) },
                remoteArchiveID: s.text(6))
        }
    }

    private func writeConflict(_ c: ConflictRecord) throws {
        try connection.run("""
            INSERT INTO conflicts (at_epoch_s, kind, subject_id, resolution, local_json, remote_json, remote_archive_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [
                SQLiteValue(c.at.epochSeconds), SQLiteValue(c.kind.rawValue), SQLiteValue(c.id),
                SQLiteValue(c.resolution.rawValue), SQLiteValue(try c.local.map(jsonText)),
                SQLiteValue(try c.remote.map(jsonText)), SQLiteValue(c.remoteArchiveID),
            ])
    }

    /// Registra un conflicto salvo que ya exista uno idéntico (mismo sujeto, resolución y versiones):
    /// así repetir una inserción no hace crecer `conflicts`.
    private func conflictOnce<L: Encodable, R: Encodable>(
        _ kind: ConflictKind, _ id: String, _ resolution: ConflictResolution,
        local: L, remote: R, archive: String?
    ) throws {
        let localJSON = try JSONValue.encoding(local)
        let remoteJSON = try JSONValue.encoding(remote)
        let localText = try jsonText(localJSON)
        let remoteText = try jsonText(remoteJSON)
        let exists = try connection.queryFirst("""
            SELECT 1 FROM conflicts WHERE subject_id = ? AND resolution = ? AND local_json IS ? AND remote_json IS ?
            """, [SQLiteValue(id), SQLiteValue(resolution.rawValue), SQLiteValue(localText), SQLiteValue(remoteText)]) { _ in true }
        guard exists == nil else { return }
        try writeConflict(ConflictRecord(at: nowInstant, kind: kind, id: id, resolution: resolution,
                                         local: localJSON, remote: remoteJSON, remoteArchiveID: archive))
    }

    private func jsonText(_ value: JSONValue) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: - Registro de paquetes

    public func recordArchive(_ a: ArchiveRecord) throws {
        try connection.transaction {
            try connection.run("""
                INSERT INTO archives (archive_id, created_at_epoch_s, path, readings, manifest_sha256, verified)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(archive_id) DO UPDATE SET path = excluded.path, verified = excluded.verified
                """, [SQLiteValue(a.archiveID), SQLiteValue(a.createdAt.epochSeconds), SQLiteValue(a.path),
                      SQLiteValue(a.readings), SQLiteValue(a.manifestSHA256), SQLiteValue(a.verified)])
        }
    }

    public func recordImportedArchive(_ a: ImportedArchiveRecord) throws {
        try connection.transaction {
            try connection.run("""
                INSERT OR IGNORE INTO imported_archives (archive_id, producer_app_id, created_at_epoch_s,
                  imported_at_epoch_s, sessions, readings, events, ledger_entries, conflicts)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [SQLiteValue(a.archiveID), SQLiteValue(a.producerAppID), SQLiteValue(a.createdAt.epochSeconds),
                      SQLiteValue(a.importedAt.epochSeconds), SQLiteValue(a.sessions), SQLiteValue(a.readings),
                      SQLiteValue(a.events), SQLiteValue(a.ledgerEntries), SQLiteValue(a.conflicts)])
        }
    }

    /// `true` si el paquete es propio o ya se importó: el importador debe omitirlo (contrato §8.1).
    public func isArchiveKnown(_ archiveID: String) throws -> Bool {
        try connection.queryFirst("""
            SELECT 1 FROM archives WHERE archive_id = ? UNION ALL SELECT 1 FROM imported_archives WHERE archive_id = ?
            """, [SQLiteValue(archiveID), SQLiteValue(archiveID)]) { _ in true } ?? false
    }

    // MARK: - event_log

    /// Escribe en `event_log`. `LogMessage` solo admite interpolaciones redactadas (`Redactor`).
    public func logEvent(_ level: EventLogLevel, category: String, _ message: LogMessage) throws {
        try connection.transaction { try logLocked(level, category: category, message) }
    }

    public func recentLogEvents(limit: Int = 100) throws -> [EventLogEntry] {
        try connection.query(
            "SELECT id, at_epoch_s, level, category, message FROM event_log ORDER BY id DESC LIMIT ?",
            [SQLiteValue(limit)]) { s in
            EventLogEntry(id: s.int64(0) ?? 0, at: UTCInstant(epochSeconds: s.int64(1) ?? 0),
                          level: s.text(2).flatMap(EventLogLevel.init(rawValue:)) ?? .info,
                          category: s.text(3) ?? "", message: s.text(4) ?? "")
        }
    }

    private func logLocked(_ level: EventLogLevel, category: String, _ message: LogMessage) throws {
        try connection.run(
            "INSERT INTO event_log (at_epoch_s, level, category, message) VALUES (?, ?, ?, ?)",
            [SQLiteValue(nowInstant.epochSeconds), SQLiteValue(level.rawValue), SQLiteValue(category),
             SQLiteValue(message.text)])
    }
}
