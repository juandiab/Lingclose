import Foundation

/// Acceso a la base de LingoScan para exportar e importar paquetes.
///
/// `SQLiteStore` mantiene su conexión privada y no expone una transacción que abarque varias operaciones, así
/// que el importador abre **su propia conexión WAL al mismo archivo** (contrato §8.5: "confirmar en una sola
/// transacción"). Esto no cambia el esquema ni las reglas del productor: el SQL de lectura/escritura repite
/// el de `SQLiteStore` y las pruebas de ida y vuelta comprueban que ambos ven lo mismo. Ver `docs/T-10.md`.
///
/// No es `Sendable`: se crea dentro de una operación síncrona y se descarta al terminar.
final class ArchiveDatabase {
    let connection: SQLiteConnection
    private let encoder = NDJSON.makeEncoder()
    private let decoder = JSONDecoder()

    init(path: String) throws {
        let c = try SQLiteConnection(path: path)
        try StoreSchema.prepare(c)
        connection = c
    }

    func transaction<T>(_ body: () throws -> T) throws -> T { try connection.transaction(body) }

    // MARK: Lectura

    func allSessions() throws -> [SensorSessionRecord] {
        try connection.query("""
            SELECT session_id, family, product_type, security_version, serial_redacted, serial_hash, firmware_hex,
              warmup_minutes, wear_minutes, activation_time_epoch_s, activation_time_source, activated_by_app_id,
              activation_source, activation_state, receiver_id_present, ended_at_epoch_s, end_reason, last_life_count,
              aliases_json, synthetic, revision, imported_from_app_id, imported_from_archive_id
            FROM sensor_sessions ORDER BY session_id
            """) { try decodeSession($0) }
    }

    func reading(recordID: String) throws -> GlucoseReading? {
        try connection.queryFirst("""
            SELECT record_id, source_record_id, session_id, life_count, analyte, unit, measured_at_epoch_s,
              received_at_epoch_s, tz_at_capture, origin, value_mgdl, capped_mgdl, uncapped_mgdl, historic_capped_mgdl,
              historic_uncapped_mgdl, historic_life_count, rate_centi, trend, actionable, temperature_centi, range_bits,
              quality_flag, channel, reserved_hex, eligible, exclusion_reason, policy_id, policy_version, decoder_id,
              decoder_version, synthetic, deleted, revision, imported_from_app_id, imported_from_archive_id
            FROM readings WHERE record_id = ?
            """, [SQLiteValue(recordID)]) { try decodeReading($0) }
    }

    func allReadings() throws -> [GlucoseReading] {
        try connection.query("""
            SELECT record_id, source_record_id, session_id, life_count, analyte, unit, measured_at_epoch_s,
              received_at_epoch_s, tz_at_capture, origin, value_mgdl, capped_mgdl, uncapped_mgdl, historic_capped_mgdl,
              historic_uncapped_mgdl, historic_life_count, rate_centi, trend, actionable, temperature_centi, range_bits,
              quality_flag, channel, reserved_hex, eligible, exclusion_reason, policy_id, policy_version, decoder_id,
              decoder_version, synthetic, deleted, revision, imported_from_app_id, imported_from_archive_id
            FROM readings ORDER BY session_id, analyte, life_count
            """) { try decodeReading($0) }
    }

    func event(id: String) throws -> DiaryEvent? {
        try connection.queryFirst("""
            SELECT event_id, kind, at_epoch_s, tz, duration_min, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
              revision, edit_id, parent_edit_id, edited_by_app_id, deleted, synthetic, imported_from_app_id,
              imported_from_archive_id
            FROM events WHERE event_id = ?
            """, [SQLiteValue(id)]) { try decodeEvent($0) }
    }

    func allEvents() throws -> [DiaryEvent] {
        try connection.query("""
            SELECT event_id, kind, at_epoch_s, tz, duration_min, carbs_g, text, created_at_epoch_s, updated_at_epoch_s,
              revision, edit_id, parent_edit_id, edited_by_app_id, deleted, synthetic, imported_from_app_id,
              imported_from_archive_id
            FROM events ORDER BY event_id
            """) { try decodeEvent($0) }
    }

    /// Cadena de ancestros desde `start` (incluido) hasta la creación, según `edit_lineage`.
    /// `complete == false` si falta un eslabón o hay un ciclo.
    func lineage(startingAt start: String?) throws -> (ids: Set<String>, links: [EditLink], complete: Bool) {
        var ids = Set<String>()
        var links: [EditLink] = []
        var current = start
        while let id = current {
            guard !ids.contains(id) else { return (ids, links, false) }
            let parent: String?? = try connection.queryFirst(
                "SELECT parent_edit_id FROM edit_lineage WHERE edit_id = ?", [SQLiteValue(id)]) { $0.text(0) }
            guard let parent else { return (ids, links, false) }
            ids.insert(id)
            links.append(EditLink(editID: id, parentEditID: parent))
            current = parent
        }
        return (ids, links, true)
    }

    func allLedger() throws -> [HealthLedgerEntry] {
        try connection.query("""
            SELECT attempt_id, subject_id, subject_kind, writer_app_id, sync_identifier, sync_version,
              exported_at_epoch_s, result
            FROM health_export_ledger ORDER BY seq
            """) { s in
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

    func allConflicts() throws -> [ConflictRecord] {
        try connection.query("""
            SELECT at_epoch_s, kind, subject_id, resolution, local_json, remote_json, remote_archive_id
            FROM conflicts ORDER BY id
            """) { s in
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

    func isArchiveKnown(_ archiveID: String) throws -> Bool {
        try connection.queryFirst("""
            SELECT 1 FROM archives WHERE archive_id = ? UNION ALL SELECT 1 FROM imported_archives WHERE archive_id = ?
            """, [SQLiteValue(archiveID), SQLiteValue(archiveID)]) { _ in true } ?? false
    }

    // MARK: Escritura

    func writeSession(_ s: SensorSessionRecord) throws {
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

    func writeReading(_ r: GlucoseReading) throws {
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

    func writeEvent(_ e: DiaryEvent) throws {
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

    func insertLineage(_ link: EditLink, eventID: String) throws {
        try connection.run(
            "INSERT OR IGNORE INTO edit_lineage (edit_id, parent_edit_id, event_id) VALUES (?, ?, ?)",
            [SQLiteValue(link.editID), SQLiteValue(link.parentEditID), SQLiteValue(eventID)])
    }

    /// `true` si el intento era nuevo (unión por `attempt_id`, §8.4).
    func insertLedger(_ entry: HealthLedgerEntry) throws -> Bool {
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

    /// Registra un conflicto salvo que ya exista uno idéntico (mismo sujeto, resolución y versiones):
    /// reimportar fotos históricas o conflictivas idénticas no hace crecer `conflicts` (draft.4).
    /// Devuelve `true` si se escribió.
    func insertConflictOnce(at: UTCInstant, kind: ConflictKind, id: String, resolution: ConflictResolution,
                            local: JSONValue?, remote: JSONValue?, remoteArchiveID: String?) throws -> Bool {
        let localText = try local.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let remoteText = try remote.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let exists = try connection.queryFirst("""
            SELECT 1 FROM conflicts WHERE subject_id = ? AND resolution = ? AND local_json IS ? AND remote_json IS ?
            """, [SQLiteValue(id), SQLiteValue(resolution.rawValue), SQLiteValue(localText), SQLiteValue(remoteText)]) { _ in true }
        guard exists == nil else { return false }
        try connection.run("""
            INSERT INTO conflicts (at_epoch_s, kind, subject_id, resolution, local_json, remote_json, remote_archive_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [SQLiteValue(at.epochSeconds), SQLiteValue(kind.rawValue), SQLiteValue(id), SQLiteValue(resolution.rawValue),
                  SQLiteValue(localText), SQLiteValue(remoteText), SQLiteValue(remoteArchiveID)])
        return true
    }

    func recordImportedArchive(archiveID: String, producerAppID: String, createdAt: UTCInstant, importedAt: UTCInstant,
                               sessions: Int, readings: Int, events: Int, ledgerEntries: Int, conflicts: Int) throws {
        try connection.run("""
            INSERT OR IGNORE INTO imported_archives (archive_id, producer_app_id, created_at_epoch_s,
              imported_at_epoch_s, sessions, readings, events, ledger_entries, conflicts)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [SQLiteValue(archiveID), SQLiteValue(producerAppID), SQLiteValue(createdAt.epochSeconds),
                  SQLiteValue(importedAt.epochSeconds), SQLiteValue(sessions), SQLiteValue(readings),
                  SQLiteValue(events), SQLiteValue(ledgerEntries), SQLiteValue(conflicts)])
    }

    /// Mensaje ya redactado por quien llama (solo contadores e identificadores públicos de paquete).
    func logEvent(at: UTCInstant, level: EventLogLevel, category: String, message: String) throws {
        try connection.run(
            "INSERT INTO event_log (at_epoch_s, level, category, message) VALUES (?, ?, ?, ?)",
            [SQLiteValue(at.epochSeconds), SQLiteValue(level.rawValue), SQLiteValue(category), SQLiteValue(message)])
    }

    // MARK: Decodificación

    private func decodeSession(_ s: SQLiteStatement) throws -> SensorSessionRecord {
        func required<T>(_ v: T?, _ column: String) throws -> T {
            guard let v else { throw StoreError.corruptRow(table: "sensor_sessions", detail: column) }
            return v
        }
        let aliases = try decoder.decode([SessionAlias].self, from: Data((s.text(18) ?? "[]").utf8))
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
}

/// Lee el estado completo de la base como contenido de paquete (para exportar y para comparar en pruebas).
public struct ArchiveSnapshotReader: Sendable {
    public let databasePath: String

    public init(databasePath: String) { self.databasePath = databasePath }

    /// Todo el estado en una sola transacción de lectura (instantánea coherente).
    public func snapshot() throws -> ArchiveContent {
        let db = try ArchiveDatabase(path: databasePath)
        return try db.transaction {
            let events = try db.allEvents()
            let arch = try events.map { e -> ArchiveEvent in
                let chain = try db.lineage(startingAt: e.parentEditID)
                return ArchiveEvent(event: e, ancestors: chain.complete ? chain.links : nil)
            }
            return ArchiveContent(sessions: try db.allSessions(), readings: try db.allReadings(), events: arch,
                                  ledger: try db.allLedger(), conflicts: try db.allConflicts())
        }
    }
}
