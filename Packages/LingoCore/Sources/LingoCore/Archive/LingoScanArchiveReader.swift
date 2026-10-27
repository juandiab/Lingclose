import Foundation

/// Lee y valida un paquete `.lingoscan` completo (contrato §8.2–§8.3). Cualquier fallo lanza el motivo exacto
/// (`ArchiveValidationError`) y no toca ninguna base: el resultado es el área de staging en memoria.
public struct LingoScanArchiveReader: Sendable {
    public init() {}

    static let mandatoryFiles = ["sessions.json", "readings.ndjson", "events.ndjson", "health_export_ledger.ndjson"]
    static let forbiddenSessionKeys = ["sensor_serial", "receiver_id", "pin_hex", "k_auth_hex", "ble", "auth",
                                       "sensor_certificate_hex", "patch_info_hex", "mac"]

    // MARK: - Manifest

    /// Valida solo lo necesario para decidir si el paquete se omite (`archive_id` conocido) o se lee entero:
    /// nombre, `manifest.json`, versiones, `snapshot.complete` y coherencia con el nombre.
    public func readManifest(at url: URL) throws -> (manifest: ArchiveManifest, sha256: String) {
        let name = url.lastPathComponent
        if ArchivePackageName.isPartial(name) { throw ArchiveValidationError.partialPackage }
        guard let parsedName = ArchivePackageName(parsing: name) else {
            throw ArchiveValidationError.notAPackage("el nombre \(name) no cumple LingoScan-<producer_tag>-<YYYYMMDDTHHMMSSZ>-<archive_id_8>.lingoscan")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ArchiveValidationError.notAPackage("\(name) no es una carpeta")
        }
        let manifestURL = url.appending(path: ArchiveManifest.fileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw ArchiveValidationError.manifestMissing }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) } catch {
            throw ArchiveValidationError.manifestInvalid("no se pudo leer: \(error.localizedDescription)")
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ArchiveValidationError.manifestInvalid("no es un objeto JSON")
        }
        // Versiones y snapshot antes de la decodificación completa: un `schema_version` futuro puede traer
        // otra estructura y debe rechazarse por su versión, no por un campo que no entendemos.
        guard let contractVersion = object["contract_version"] as? String,
              let major = ArchiveManifest.major(ofContractVersion: contractVersion) else {
            throw ArchiveValidationError.manifestInvalid("contract_version ausente o ilegible")
        }
        guard major == ArchiveManifest.supportedContractMajor else {
            throw ArchiveValidationError.unsupportedContractVersion(contractVersion)
        }
        guard let schemaVersion = Self.integer(object["schema_version"]), schemaVersion >= 1 else {
            throw ArchiveValidationError.manifestInvalid("schema_version ausente o no es un entero ≥ 1")
        }
        guard schemaVersion <= ArchiveManifest.supportedSchemaVersion else {
            throw ArchiveValidationError.unsupportedSchemaVersion(found: schemaVersion, supported: ArchiveManifest.supportedSchemaVersion)
        }
        guard let snapshotObject = object["snapshot"] as? [String: Any],
              (snapshotObject["complete"] as? NSNumber).map({ CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue }) == true else {
            throw ArchiveValidationError.snapshotIncomplete
        }
        try Self.requireKeys(object, ["contract_version", "schema_version", "archive_id", "created_at_utc", "producer", "device",
                                      "snapshot", "policy", "health", "counts", "files", "synthetic"], in: "manifest.json") { .manifestInvalid($0) }
        for (key, keys) in [("producer", ["app_id", "producer_tag", "app_name", "app_version", "build", "decoder_id", "decoder_version"]),
                            ("device", ["model", "os_version"]),
                            ("snapshot", ["kind", "from_utc", "to_utc", "complete"]),
                            ("policy", ["eligibility_policy_id", "eligibility_policy_version"]),
                            ("health", ["writer_app_id", "handover_at_utc", "last_confirmed_measured_at_utc", "pending_subjects"]),
                            ("counts", ["sessions", "readings", "events", "ledger_entries", "conflicts"])] {
            guard let nested = object[key] as? [String: Any] else {
                throw ArchiveValidationError.manifestInvalid("\(key) no es un objeto")
            }
            try Self.requireKeys(nested, keys, in: "manifest.json \(key)") { .manifestInvalid($0) }
        }
        let manifest: ArchiveManifest
        do { manifest = try JSONDecoder().decode(ArchiveManifest.self, from: data) } catch {
            throw ArchiveValidationError.manifestInvalid(Self.describe(error))
        }
        guard RecordID.isLowercaseUUIDv4(manifest.archiveID) else {
            throw ArchiveValidationError.manifestInvalid("archive_id no es un UUID v4 en minúsculas")
        }
        if manifest.snapshot.kind == .partial && manifest.snapshot.from == nil {
            throw ArchiveValidationError.manifestInvalid("snapshot.kind partial exige from_utc")
        }
        guard String(manifest.archiveID.prefix(8)) == parsedName.archiveID8 else {
            throw ArchiveValidationError.nameMismatch("archive_id \(manifest.archiveID.prefix(8)) frente al sufijo \(parsedName.archiveID8)")
        }
        guard manifest.createdAt == parsedName.createdAt else {
            throw ArchiveValidationError.nameMismatch("created_at_utc \(manifest.createdAt) frente a la marca de tiempo de la carpeta")
        }
        return (manifest, ArchiveHashing.sha256Hex(data))
    }

    // MARK: - Paquete completo

    public func read(at url: URL) throws -> ArchivePackage {
        let (manifest, manifestSHA) = try readManifest(at: url)
        var warnings: [String] = []

        // Archivos listados: existencia, bytes y SHA-256.
        var blobs: [String: Data] = [:]
        for entry in manifest.files {
            let n = entry.name
            guard !n.isEmpty, !n.contains("/"), !n.contains("\\"), n != ".", n != "..", n != ArchiveManifest.fileName else {
                throw ArchiveValidationError.invalidFileName(n)
            }
            guard blobs[n] == nil else { throw ArchiveValidationError.manifestInvalid("archivo listado dos veces: \(n)") }
            let fileURL = url.appending(path: n, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { throw ArchiveValidationError.fileMissing(n) }
            let data: Data
            do { data = try Data(contentsOf: fileURL) } catch { throw ArchiveValidationError.fileMissing(n) }
            guard data.count == entry.bytes else {
                throw ArchiveValidationError.sizeMismatch(file: n, expected: entry.bytes, actual: data.count)
            }
            let actual = ArchiveHashing.sha256Hex(data)
            guard actual == entry.sha256 else {
                throw ArchiveValidationError.hashMismatch(file: n, expected: entry.sha256, actual: actual)
            }
            blobs[n] = data
        }
        for n in Self.mandatoryFiles where blobs[n] == nil { throw ArchiveValidationError.mandatoryFileNotListed(n) }
        let present = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let unlisted = present.filter { blobs[$0] == nil && $0 != ArchiveManifest.fileName && $0 != "README.md" && !$0.hasPrefix(".") }
        if !unlisted.isEmpty { warnings.append("archivos presentes y no listados (se ignoran): \(unlisted.sorted().joined(separator: ", "))") }

        // Sesiones.
        let sessions = try Self.parseSessions(blobs["sessions.json"]!)
        // NDJSON.
        let readings = try Self.parseReadings(blobs["readings.ndjson"]!)
        let events = try Self.parseEvents(blobs["events.ndjson"]!)
        let ledger = try Self.parseLedger(blobs["health_export_ledger.ndjson"]!)
        let conflicts = try blobs["conflicts.ndjson"].map(Self.parseConflicts) ?? []
        var csvRows: Int?
        if let csv = blobs["readings.csv"] {
            csvRows = try Self.checkCSV(csv)
        }

        let content = ArchiveContent(sessions: sessions, readings: readings, events: events, ledger: ledger, conflicts: conflicts)
        try Self.checkCrossRecord(manifest: manifest, content: content, warnings: &warnings)

        // Conteos.
        let actual: [String: Int] = [
            "sessions.json": sessions.count, "readings.ndjson": readings.count, "events.ndjson": events.count,
            "health_export_ledger.ndjson": ledger.count, "conflicts.ndjson": conflicts.count,
        ]
        for entry in manifest.files {
            let real = actual[entry.name] ?? (entry.name == "readings.csv" ? csvRows : nil)
            if let real, real != entry.records {
                throw ArchiveValidationError.countMismatch("\(entry.name): records \(entry.records), pero tiene \(real)")
            }
        }
        let counts = manifest.counts
        for (label, declared, real) in [("sessions", counts.sessions, sessions.count), ("readings", counts.readings, readings.count),
                                        ("events", counts.events, events.count), ("ledger_entries", counts.ledgerEntries, ledger.count),
                                        ("conflicts", counts.conflicts, conflicts.count)] where declared != real {
            throw ArchiveValidationError.countMismatch("counts.\(label) = \(declared), pero el archivo tiene \(real)")
        }
        return ArchivePackage(url: url, manifest: manifest, manifestSHA256: manifestSHA, content: content, warnings: warnings)
    }

    // MARK: - Parsers de archivos

    static func parseSessions(_ data: Data) throws -> [SensorSessionRecord] {
        let file = "sessions.json"
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { throw ArchiveValidationError.invalidFile(file: file, detail: "lleva BOM") }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let array = root["sessions"] as? [Any] else {
            throw ArchiveValidationError.invalidFile(file: file, detail: "se esperaba un objeto {\"sessions\": […]}")
        }
        var out: [SensorSessionRecord] = []
        for (i, element) in array.enumerated() {
            let line = i + 1
            guard let object = element as? [String: Any] else {
                throw ArchiveValidationError.invalidLine(file: file, line: line, detail: "la sesión no es un objeto")
            }
            for key in forbiddenSessionKeys where object[key] != nil { throw ArchiveValidationError.forbiddenSessionKey(key) }
            try requireKeys(object, ["session_id", "sensor_family", "product_type", "security_version", "sensor_serial_hash",
                                     "warmup_minutes", "wear_minutes", "activation_time_epoch_s", "activation_time_source",
                                     "activated_at_utc", "activated_by_app_id", "activation_source", "receiver_id_present",
                                     "ended_at_utc", "end_reason", "last_life_count", "revision", "imported_from", "aliases",
                                     "synthetic"], in: file, line: line)
            let objectData = try JSONSerialization.data(withJSONObject: object)
            let s: SensorSessionRecord = try decode(objectData, file: file, line: line)
            try validate(session: s, object: object, file: file, line: line)
            out.append(s)
        }
        var seen = Set<String>()
        for s in out where !seen.insert(s.sessionID).inserted {
            throw ArchiveValidationError.invalidRecord(file: file, detail: "session_id duplicado: \(s.sessionID)")
        }
        return out
    }

    static func parseReadings(_ data: Data) throws -> [GlucoseReading] {
        let file = "readings.ndjson"
        var out: [GlucoseReading] = []
        for (n, bytes) in try NDJSON.lines(of: data, file: file) {
            let object = try jsonObject(bytes, file: file, line: n)
            try requireKeys(object, ["record_id", "session_id", "life_count", "analyte", "unit", "measured_at_utc", "received_at_utc",
                                     "tz_at_capture", "origin", "value", "raw", "eligibility", "decoder", "revision", "deleted",
                                     "imported_from", "source_record_id", "synthetic"], in: file, line: n)
            for (key, keys) in [("raw", ["capped", "uncapped", "historic_capped", "historic_uncapped", "historic_life_count", "rate_centi",
                                         "trend", "actionable", "temperature_centi", "range_bits", "quality_flag", "channel"]),
                                ("eligibility", ["status", "reason", "policy_id", "policy_version"]),
                                ("decoder", ["id", "version"])] {
                guard let nested = object[key] as? [String: Any] else {
                    throw ArchiveValidationError.invalidLine(file: file, line: n, detail: "\(key) no es un objeto")
                }
                try requireKeys(nested, keys, in: file, line: n, path: key)
            }
            let r: GlucoseReading = try decode(bytes, file: file, line: n)
            try validate(reading: r, object: object, file: file, line: n)
            out.append(r)
        }
        var seen = Set<String>()
        for r in out where !seen.insert(r.recordID).inserted {
            throw ArchiveValidationError.invalidRecord(file: file, detail: "record_id duplicado: \(r.recordID)")
        }
        return out
    }

    static func parseEvents(_ data: Data) throws -> [ArchiveEvent] {
        let file = "events.ndjson"
        var out: [ArchiveEvent] = []
        for (n, bytes) in try NDJSON.lines(of: data, file: file) {
            let object = try jsonObject(bytes, file: file, line: n)
            try requireKeys(object, ["event_id", "kind", "at_utc", "tz", "duration_min", "carbs_g", "text", "created_at_utc",
                                     "updated_at_utc", "revision", "deleted", "imported_from", "edit_id", "parent_edit_id",
                                     "edited_by_app_id", "synthetic"], in: file, line: n)
            let e: DiaryEvent = try decode(bytes, file: file, line: n)
            var ancestors: [EditLink]?
            if object["edit_ancestors"] != nil {
                guard let raw = object["edit_ancestors"] as? [Any] else {
                    throw ArchiveValidationError.invalidLine(file: file, line: n, detail: "edit_ancestors no es una lista")
                }
                var chain: [EditLink] = []
                for item in raw {
                    guard let o = item as? [String: Any], Set(o.keys) == ["edit_id", "parent_edit_id"] else {
                        throw ArchiveValidationError.invalidLine(file: file, line: n, detail: "edit_ancestors: elemento sin exactamente edit_id y parent_edit_id")
                    }
                    chain.append(try decode(try JSONSerialization.data(withJSONObject: o), file: file, line: n))
                }
                ancestors = chain
            }
            try validate(event: e, ancestors: ancestors, object: object, file: file, line: n)
            out.append(ArchiveEvent(event: e, ancestors: ancestors))
        }
        var events = Set<String>(), edits = Set<String>()
        for a in out {
            guard events.insert(a.event.eventID).inserted else {
                throw ArchiveValidationError.invalidRecord(file: file, detail: "event_id duplicado: \(a.event.eventID)")
            }
            guard edits.insert(a.event.editID).inserted else {
                throw ArchiveValidationError.invalidRecord(file: file, detail: "edit_id duplicado: \(a.event.editID)")
            }
        }
        return out
    }

    static func parseLedger(_ data: Data) throws -> [HealthLedgerEntry] {
        let file = "health_export_ledger.ndjson"
        var out: [HealthLedgerEntry] = []
        for (n, bytes) in try NDJSON.lines(of: data, file: file) {
            let object = try jsonObject(bytes, file: file, line: n)
            try requireKeys(object, ["subject_id", "subject_kind", "writer_app_id", "sync_identifier", "sync_version",
                                     "exported_at_utc", "result", "attempt_id"], in: file, line: n)
            let l: HealthLedgerEntry = try decode(bytes, file: file, line: n)
            guard RecordID.isLowercaseUUIDv4(l.attemptID) else { throw lineError(file, n, "attempt_id no es un UUID v4") }
            guard !l.writerAppID.isEmpty, !l.syncIdentifier.isEmpty, l.syncVersion >= 0 else {
                throw lineError(file, n, "writer_app_id, sync_identifier o sync_version inválidos")
            }
            switch l.subjectKind {
            case .glucose:
                guard RecordID(parsing: l.subjectID) != nil else { throw lineError(file, n, "subject_id de glucosa no es un record_id") }
            case .carbs, .energyKcal, .proteinG, .fatG:
                guard RecordID.isLowercaseUUIDv4(l.subjectID) else { throw lineError(file, n, "subject_id de comida no es un event_id") }
            }
            out.append(l)
        }
        var seen = Set<String>()
        for l in out where !seen.insert(l.attemptID).inserted {
            throw ArchiveValidationError.invalidRecord(file: file, detail: "attempt_id duplicado: \(l.attemptID)")
        }
        return out
    }

    static func parseConflicts(_ data: Data) throws -> [ConflictRecord] {
        let file = "conflicts.ndjson"
        var out: [ConflictRecord] = []
        for (n, bytes) in try NDJSON.lines(of: data, file: file) {
            let object = try jsonObject(bytes, file: file, line: n)
            try requireKeys(object, ["at_utc", "kind", "id", "resolution"], in: file, line: n)
            let c: ConflictRecord = try decode(bytes, file: file, line: n)
            guard !c.id.isEmpty else { throw lineError(file, n, "id vacío") }
            if c.resolution == .divergent {
                guard c.local != nil, c.remote != nil, let archive = c.remoteArchiveID, RecordID.isLowercaseUUIDv4(archive) else {
                    throw lineError(file, n, "un conflicto divergent exige local, remote y remote_archive_id")
                }
            }
            out.append(c)
        }
        return out
    }

    /// Cabecera exacta de §5.6; devuelve el número de filas.
    static func checkCSV(_ data: Data) throws -> Int {
        let file = "readings.csv"
        guard let text = String(data: data, encoding: .utf8) else {
            throw ArchiveValidationError.invalidFile(file: file, detail: "no es UTF-8 válido")
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last == "" { lines.removeLast() }
        guard lines.first.map(String.init) == CSVWriter.header else {
            throw ArchiveValidationError.invalidFile(file: file, detail: "cabecera distinta de la fija de §5.6")
        }
        return max(lines.count - 1, 0)
    }

    // MARK: - Reglas por registro

    static func validate(session s: SensorSessionRecord, object: [String: Any], file: String, line: Int) throws {
        func fail(_ d: String) -> ArchiveValidationError { lineError(file, line, "sesión \(s.sessionID): \(d)") }
        guard RecordID.isLowercaseUUIDv4(s.sessionID) else { throw fail("session_id no es un UUID v4 en minúsculas") }
        guard s.sensorSerialHash.count == 64, isLowerHex(s.sensorSerialHash) else { throw fail("sensor_serial_hash no es SHA-256 hex") }
        guard (0...255).contains(s.productType), (0...65_535).contains(s.securityVersion) else { throw fail("product_type o security_version fuera de rango") }
        guard s.warmupMinutes >= 0, s.wearMinutes >= 0, s.activationTimeEpochS >= 0, s.revision >= 1 else { throw fail("enteros fuera de rango") }
        if let lc = s.lastLifeCount, !(0...65_535).contains(lc) { throw fail("last_life_count fuera de 0...65535") }
        if let hex = s.firmwareHex, !(hex.count == 8 && isLowerHex(hex)) { throw fail("firmware_hex no son 4 bytes en hex") }
        if let red = s.sensorSerialRedacted, !(red.count == 4 && red.hasSuffix("…")) { throw fail("sensor_serial_redacted no es 3 caracteres + …") }
        guard !s.activatedByAppID.isEmpty else { throw fail("activated_by_app_id vacío") }
        guard UTCInstant(epochSeconds: s.activationTimeEpochS).rfc3339 == (object["activated_at_utc"] as? String) else {
            throw fail("activated_at_utc no corresponde a activation_time_epoch_s")
        }
        if let from = s.importedFrom, !RecordID.isLowercaseUUIDv4(from.archiveID) || from.appID.isEmpty { throw fail("imported_from inválido") }
        var aliasIDs = Set<String>()
        for a in s.aliases {
            guard RecordID.isLowercaseUUIDv4(a.sessionID), RecordID.isLowercaseUUIDv4(a.archiveID), !a.appID.isEmpty else {
                throw fail("alias inválido")
            }
            guard a.sessionID != s.sessionID else { throw fail("aliases contiene el propio session_id") }
            guard aliasIDs.insert(a.sessionID).inserted else { throw fail("aliases con session_id repetido") }
        }
    }

    static func validate(reading r: GlucoseReading, object: [String: Any], file: String, line: Int) throws {
        func fail(_ d: String) -> ArchiveValidationError { lineError(file, line, d) }
        guard RecordID.isLowercaseUUIDv4(r.sessionID) else { throw fail("session_id no es un UUID v4 en minúsculas") }
        guard RecordID.lifeCountRange.contains(r.lifeCount) else { throw fail("life_count fuera de 0...65535") }
        guard r.recordID == RecordID.make(sessionID: r.sessionID, analyte: r.analyte, lifeCount: r.lifeCount),
              RecordID(parsing: r.recordID) != nil else { throw fail("record_id no coincide con session_id:analyte:life_count") }
        if let source = r.sourceRecordID, RecordID(parsing: source) == nil { throw fail("source_record_id con formato inválido") }
        guard r.unit == "mg/dL" else { throw fail("unit debe ser mg/dL") }
        guard isIANA(r.tzAtCapture) else { throw fail("tz_at_capture no es un nombre IANA") }
        guard r.revision >= 1 else { throw fail("revision < 1") }
        guard !r.decoder.id.isEmpty, !r.decoder.version.isEmpty, !r.eligibility.policyID.isEmpty,
              !r.eligibility.policyVersion.isEmpty else { throw fail("decoder o policy vacíos") }
        if let from = r.importedFrom, !RecordID.isLowercaseUUIDv4(from.archiveID) || from.appID.isEmpty { throw fail("imported_from inválido") }
        let raw = r.raw
        for (label, v, range) in [("capped", raw.capped, 0...4095), ("uncapped", raw.uncapped, 0...4095),
                                  ("historic_capped", raw.historicCapped, 0...4095), ("historic_uncapped", raw.historicUncapped, 0...4095),
                                  ("historic_life_count", raw.historicLifeCount, 0...65_535), ("rate_centi", raw.rateCenti, -32_767...32_767),
                                  ("trend", raw.trend, 0...5), ("temperature_centi", raw.temperatureCenti, -32_767...32_767),
                                  ("range_bits", raw.rangeBits, 0...3), ("channel", raw.channel, 0...1)] {
            if let v, !range.contains(v) { throw fail("raw.\(label) fuera de rango") }
        }
        if let hex = raw.reservedHex, !(hex.count % 2 == 0 && isLowerHex(hex)) { throw fail("raw.reserved_hex no es hex en minúsculas") }
        // `value`: nulo si borrada o excluida; entero si elegible y no borrada (reading.schema.json).
        if r.deleted || !r.eligibility.isEligible {
            guard r.value == nil else { throw fail("value debe ser null en una lectura borrada o excluida") }
        } else {
            guard r.value != nil else { throw fail("una lectura elegible debe traer value") }
        }
        if r.deleted {
            guard r.eligibility.reason == .deleted else { throw fail("un tombstone debe ser excluded/deleted") }
        }
        if let v = r.value, !(0...4095).contains(v) { throw fail("value fuera de rango") }
    }

    static func validate(event e: DiaryEvent, ancestors: [EditLink]?, object: [String: Any], file: String, line: Int) throws {
        func fail(_ d: String) -> ArchiveValidationError { lineError(file, line, d) }
        guard RecordID.isLowercaseUUIDv4(e.eventID), RecordID.isLowercaseUUIDv4(e.editID) else { throw fail("event_id o edit_id no es UUID v4") }
        if let p = e.parentEditID {
            guard RecordID.isLowercaseUUIDv4(p) else { throw fail("parent_edit_id no es UUID v4") }
            guard p != e.editID else { throw fail("parent_edit_id igual a edit_id") }
        }
        guard isIANA(e.tz) else { throw fail("tz no es un nombre IANA") }
        guard e.revision >= 1, !e.editedByAppID.isEmpty else { throw fail("revision o edited_by_app_id inválidos") }
        if let d = e.durationMin, d < 0 { throw fail("duration_min negativo") }
        if let c = e.carbsG, c < 0 || !c.isFinite { throw fail("carbs_g inválido") }
        if let t = e.text, t.count > 2000 { throw fail("text excede 2000 caracteres") }
        if let from = e.importedFrom, !RecordID.isLowercaseUUIDv4(from.archiveID) || from.appID.isEmpty { throw fail("imported_from inválido") }
        if let ancestors {
            // Cadena continua desde parent_edit_id hasta la creación, sin ciclos ni saltos (draft.4).
            var expected = e.parentEditID
            var visited: Set<String> = [e.editID]
            for a in ancestors {
                guard RecordID.isLowercaseUUIDv4(a.editID), let want = expected, a.editID == want, !visited.contains(want) else {
                    throw fail("edit_ancestors incompleta, inconexa o cíclica")
                }
                visited.insert(want)
                expected = a.parentEditID
            }
            guard expected == nil else { throw fail("edit_ancestors no llega a la creación") }
        }
    }

    /// Reglas entre registros: sesiones de las lecturas y procedencia sintética (§4, C6, ajuste de Astra).
    static func checkCrossRecord(manifest: ArchiveManifest, content: ArchiveContent, warnings: inout [String]) throws {
        let sessions = Dictionary(uniqueKeysWithValues: content.sessions.map { ($0.sessionID, $0) })
        for r in content.readings {
            guard let s = sessions[r.sessionID] else {
                throw ArchiveValidationError.invalidRecord(file: "readings.ndjson", detail: "session_id \(r.sessionID) no existe en sessions.json")
            }
            // Ajuste de Astra: una lectura real no puede pertenecer a una sesión sintética, aunque el manifest no sea sintético.
            if s.synthetic && !r.synthetic {
                throw ArchiveValidationError.syntheticInconsistency("la lectura \(r.recordID) es real pero su sesión es sintética")
            }
            let expected = r.measuredAt.epochSeconds - (s.activationTimeEpochS + 60 * Int64(r.lifeCount))
            if abs(expected) > 90 { warnings.append("measured_at_utc de \(r.recordID) se aleja más de 90 s de activación + 60·life_count") }
        }
        if manifest.synthetic {
            if let s = content.sessions.first(where: { !$0.synthetic }) {
                throw ArchiveValidationError.syntheticInconsistency("manifest sintético con la sesión real \(s.sessionID)")
            }
            if let r = content.readings.first(where: { !$0.synthetic }) {
                throw ArchiveValidationError.syntheticInconsistency("manifest sintético con la lectura real \(r.recordID)")
            }
            if let e = content.events.first(where: { !$0.event.synthetic }) {
                throw ArchiveValidationError.syntheticInconsistency("manifest sintético con el evento real \(e.event.eventID)")
            }
        }
    }

    // MARK: - Utilidades

    static func lineError(_ file: String, _ line: Int, _ detail: String) -> ArchiveValidationError {
        .invalidLine(file: file, line: line, detail: detail)
    }

    static func integer(_ any: Any?) -> Int? {
        guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == Double(n.intValue) else { return nil }
        return n.intValue
    }

    static func requireKeys(_ object: [String: Any], _ keys: [String], in file: String, line: Int? = nil, path: String? = nil) throws {
        try requireKeys(object, keys, in: file + (path.map { " \($0)" } ?? "")) { detail in
            line.map { .invalidLine(file: file, line: $0, detail: detail) } ?? .invalidFile(file: file, detail: detail)
        }
    }

    static func requireKeys(_ object: [String: Any], _ keys: [String], in label: String,
                            _ make: (String) -> ArchiveValidationError) throws {
        for k in keys where object[k] == nil { throw make("falta el campo obligatorio '\(k)' en \(label)") }
    }

    static func jsonObject(_ bytes: Data, file: String, line: Int) throws -> [String: Any] {
        do {
            guard let o = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw lineError(file, line, "la línea no es un objeto JSON")
            }
            return o
        } catch let e as ArchiveValidationError {
            throw e
        } catch {
            throw lineError(file, line, "JSON inválido")
        }
    }

    static func decode<T: Decodable>(_ bytes: Data, file: String, line: Int) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: bytes) } catch {
            throw lineError(file, line, describe(error))
        }
    }

    /// Descripción corta de un error de decodificación, sin volcar el contenido.
    static func describe(_ error: any Error) -> String {
        guard let e = error as? DecodingError else { return "JSON inválido" }
        func path(_ c: DecodingError.Context) -> String { c.codingPath.map(\.stringValue).joined(separator: ".") }
        switch e {
        case .keyNotFound(let k, let c): return "falta \(k.stringValue) en \(path(c))"
        case .typeMismatch(_, let c): return "tipo inválido en \(path(c))"
        case .valueNotFound(_, let c): return "valor ausente en \(path(c))"
        case .dataCorrupted(let c): return "valor inválido en \(path(c)): \(c.debugDescription)"
        @unknown default: return "JSON inválido"
        }
    }

    static func isLowerHex(_ s: String) -> Bool {
        s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// `^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$`
    static func isIANA(_ s: String) -> Bool {
        let segments = s.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = segments.first?.first, first.isASCII, first.isLetter else { return false }
        return segments.allSatisfy { seg in
            !seg.isEmpty && seg.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "+" || $0 == "-") }
        }
    }
}
