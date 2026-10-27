import Foundation

/// Importa paquetes `.lingoscan` aplicando las reglas de unión del contrato §8 y §5 (`1.0.0-draft.4`)
/// sobre la base de LingoScan, **en una sola transacción** por paquete.
///
/// El paquete se lee y valida entero en memoria (staging) antes de abrir la transacción; cualquier fallo de
/// validación lanza `ArchiveValidationError` y no toca la base. Reglas de lecturas (§8.4), en este orden:
/// tombstones pegajosos, sintéticos, `raw` equivalente, rutas distintas, local elegible, sin local.
public struct ArchiveImporter: Sendable {
    public let databasePath: String
    public let localPolicy: any ArchiveEligibilityPolicy
    private let now: @Sendable () -> Date

    public init(databasePath: String, localPolicy: any ArchiveEligibilityPolicy = LingoScanV1ArchivePolicy(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.databasePath = databasePath
        self.localPolicy = localPolicy
        self.now = now
    }

    /// Lee, valida e importa un paquete. Si su `archive_id` ya es conocido, devuelve `alreadyKnown` sin validar más.
    public func importPackage(at url: URL) throws -> ImportSummary {
        let reader = LingoScanArchiveReader()
        let (manifest, _) = try reader.readManifest(at: url)
        let db = try ArchiveDatabase(path: databasePath)
        if try db.isArchiveKnown(manifest.archiveID) {
            return ImportSummary(archiveID: manifest.archiveID, producerAppID: manifest.producer.appID,
                                 createdAt: manifest.createdAt, alreadyKnown: true, handoverAt: manifest.health.handoverAt)
        }
        return try importPackage(try reader.read(at: url), using: db)
    }

    /// Importa un paquete ya validado.
    public func importPackage(_ package: ArchivePackage) throws -> ImportSummary {
        try importPackage(package, using: try ArchiveDatabase(path: databasePath))
    }

    /// Importa todas las carpetas `*.lingoscan` de `folder` (las `*.partial` se ignoran), de la más antigua a la
    /// más reciente. Un paquete inválido no impide importar los demás.
    public func importAll(in folder: URL) -> [PackageImportOutcome] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(ArchivePackageName.suffix) && !ArchivePackageName.isPartial($0) }
            .sorted()
        return names.map { importOutcome(at: folder.appending(path: $0, directoryHint: .isDirectory)) }
    }

    /// Importa un paquete y convierte cualquier fallo en un resultado, para recorrer carpetas sin abortar.
    public func importOutcome(at url: URL) -> PackageImportOutcome {
        let name = url.lastPathComponent
        do {
            let summary = try importPackage(at: url)
            return summary.alreadyKnown ? .skipped(summary) : .imported(summary)
        } catch let e as ArchiveValidationError {
            return .rejected(name: name, reason: e.localizedDescription, code: e.code)
        } catch {
            return .rejected(name: name, reason: "\(error)", code: "store_error")
        }
    }

    private func importPackage(_ package: ArchivePackage, using db: ArchiveDatabase) throws -> ImportSummary {
        try db.transaction {
            let manifest = package.manifest
            if try db.isArchiveKnown(manifest.archiveID) {
                return ImportSummary(archiveID: manifest.archiveID, producerAppID: manifest.producer.appID,
                                     createdAt: manifest.createdAt, alreadyKnown: true, handoverAt: manifest.health.handoverAt)
            }
            let run = ImportRun(db: db, package: package, policy: localPolicy, importedAt: UTCInstant(now()))
            try run.execute()
            return run.summary
        }
    }
}

// MARK: - Unión

/// Traducción de `session_id` de un paquete al canónico local (§5.1, C1).
struct SessionTranslation {
    var canonical: [String: String] = [:]
    /// Sesiones (y alias) cuyos registros no entran: sintética contra real.
    var dropped: Set<String> = []
}

/// Una importación en curso. Todo ocurre dentro de la transacción abierta por `ArchiveImporter`.
final class ImportRun {
    let db: ArchiveDatabase
    let package: ArchivePackage
    let policy: any ArchiveEligibilityPolicy
    let source: ImportedFrom
    let importedAt: UTCInstant
    var summary: ImportSummary
    private var sessions: [String: SensorSessionRecord] = [:]
    private var translation = SessionTranslation()

    init(db: ArchiveDatabase, package: ArchivePackage, policy: any ArchiveEligibilityPolicy, importedAt: UTCInstant) {
        self.db = db
        self.package = package
        self.policy = policy
        self.importedAt = importedAt
        let m = package.manifest
        source = ImportedFrom(appID: m.producer.appID, archiveID: m.archiveID)
        summary = ImportSummary(archiveID: m.archiveID, producerAppID: m.producer.appID, createdAt: m.createdAt,
                                alreadyKnown: false, handoverAt: m.health.handoverAt)
        summary.warnings = package.warnings
    }

    func execute() throws {
        for s in try db.allSessions() { sessions[s.sessionID] = s }
        try mergeSessions()
        try mergeReadings()
        try mergeEvents()
        try mergeLedger()
        try db.recordImportedArchive(
            archiveID: summary.archiveID, producerAppID: summary.producerAppID, createdAt: summary.createdAt,
            importedAt: importedAt, sessions: package.content.sessions.count, readings: package.content.readings.count,
            events: package.content.events.count, ledgerEntries: package.content.ledger.count,
            conflicts: summary.conflictsRecorded)
        try db.logEvent(at: importedAt, level: .info, category: "archive_import",
                        message: "paquete \(summary.archiveID.prefix(8)) de \(summary.producerAppID): "
                            + "\(summary.readings.new) lecturas nuevas, \(summary.readings.updated) actualizadas, "
                            + "\(summary.conflictsRecorded) conflictos, \(summary.rejected) rechazados")
    }

    // MARK: Conflictos

    private func record(_ kind: ConflictKind, _ id: String, _ resolution: ConflictResolution,
                        local: JSONValue?, remote: JSONValue?) throws {
        if try db.insertConflictOnce(at: package.manifest.createdAt, kind: kind, id: id, resolution: resolution,
                                     local: local, remote: remote, remoteArchiveID: source.archiveID) {
            summary.conflictsRecorded += 1
        }
    }

    // MARK: Sesiones (§5.1, C1)

    /// Canónico local de un UUID, por `session_id` o por alias.
    private func localCanonical(of id: String) -> String? {
        for key in sessions.keys.sorted() {
            let s = sessions[key]!
            if key == id || s.aliases.contains(where: { $0.sessionID == id }) { return key }
        }
        return nil
    }

    /// Sesión local que es la misma que `remote`: por UUID o alias, y si no por sensor + activación ±120 s.
    /// La equivalencia física exige activación conocida en ambas (`> 0`).
    private func matchLocal(for remote: SensorSessionRecord) -> String? {
        let ids = Set([remote.sessionID] + remote.aliases.map(\.sessionID))
        for key in sessions.keys.sorted() {
            let s = sessions[key]!
            if !ids.isDisjoint(with: Set([key] + s.aliases.map(\.sessionID))) { return key }
        }
        guard remote.activationTimeEpochS > 0 else { return nil }
        for key in sessions.keys.sorted() {
            let s = sessions[key]!
            if s.sensorSerialHash == remote.sensorSerialHash, s.activationTimeEpochS > 0,
               abs(s.activationTimeEpochS - remote.activationTimeEpochS) <= 120 { return key }
        }
        return nil
    }

    private func mergeSessions() throws {
        for remote in package.content.sessions.sorted(by: { $0.sessionID < $1.sessionID }) {
            guard let canonicalID = matchLocal(for: remote) else {
                var new = remote
                new.importedFrom = source
                try db.writeSession(new)
                sessions[new.sessionID] = new
                translation.canonical[remote.sessionID] = remote.sessionID
                summary.sessions.new += 1
                continue
            }
            var local = sessions[canonicalID]!
            // Una sesión sintética nunca se fusiona con una real: kept_local y sus registros no entran.
            guard local.synthetic == remote.synthetic else {
                try record(.session, canonicalID, .keptLocal, local: try JSONValue.encoding(local), remote: try JSONValue.encoding(remote))
                translation.dropped.insert(remote.sessionID)
                for a in remote.aliases { translation.dropped.insert(a.sessionID) }
                summary.sessions.conflicted += 1
                continue
            }
            let before = local
            translation.canonical[remote.sessionID] = canonicalID
            var known = Set(local.aliases.map(\.sessionID))
            var added = false
            if remote.sessionID != canonicalID, !known.contains(remote.sessionID) {
                // recorded_at_utc = created_at_utc del paquete que trae el alias: determinista, no el reloj del importador.
                local.aliases.append(SessionAlias(sessionID: remote.sessionID, appID: source.appID,
                                                  archiveID: source.archiveID, recordedAt: package.manifest.createdAt))
                known.insert(remote.sessionID)
                added = true
            }
            for a in remote.aliases {
                translation.canonical[a.sessionID] = canonicalID
                if a.sessionID != canonicalID, !known.contains(a.sessionID) {
                    local.aliases.append(a)
                    known.insert(a.sessionID)
                }
            }
            local.aliases.sort { $0.sessionID < $1.sessionID }
            if local.aliases != before.aliases {
                local.revision = before.revision + 1
                try db.writeSession(local)
                sessions[canonicalID] = local
                summary.sessions.updated += 1
            } else {
                summary.sessions.identical += 1
            }
            if added {
                try record(.session, canonicalID, .aliased, local: try JSONValue.encoding(before), remote: try JSONValue.encoding(remote))
            }
        }
    }

    // MARK: Lecturas (§8.4)

    private func mergeReadings() throws {
        let psyn = package.manifest.synthetic
        let ordered = package.content.readings.sorted {
            ($0.sessionID, $0.analyte.rawValue, $0.lifeCount) < ($1.sessionID, $1.analyte.rawValue, $1.lifeCount)
        }
        for original in ordered {
            if translation.dropped.contains(original.sessionID) {
                summary.rejected += 1
                continue
            }
            var remote = original
            let canonical = translation.canonical[original.sessionID] ?? localCanonical(of: original.sessionID) ?? original.sessionID
            if canonical != original.sessionID {
                // §5.1 paso 3: record_id recalculado con el canónico; el original queda en source_record_id.
                remote.sourceRecordID = original.sourceRecordID ?? original.recordID
                remote.sessionID = canonical
                remote.recordID = RecordID.make(sessionID: canonical, analyte: original.analyte, lifeCount: original.lifeCount)
            }
            let local = try db.reading(recordID: remote.recordID)
            let warmup = sessions[canonical]?.warmupMinutes ?? 60
            let result = ReadingMerge.decide(local: local, remote: remote, source: source, policy: policy,
                                             warmupMinutes: warmup, packageSynthetic: psyn)
            if let write = result.write { try db.writeReading(write) }
            for c in result.conflicts {
                try record(.reading, remote.recordID, c.resolution,
                           local: try c.local.map { try JSONValue.encoding($0) }, remote: try JSONValue.encoding(c.remote))
            }
            switch result.outcome {
            case .new: summary.readings.new += 1
            case .updated: summary.readings.updated += 1
            case .identical: summary.readings.identical += 1
            case .conflicted: summary.readings.conflicted += 1
            }
        }
    }

    // MARK: Eventos (§5.3, C3)

    private func mergeEvents() throws {
        // Primero se aprende todo el linaje remoto (draft.4: los ancestros viajan en el paquete).
        for a in package.content.events {
            for link in (a.ancestors ?? []) + [a.event.editLink] { try db.insertLineage(link, eventID: a.event.eventID) }
        }
        for a in package.content.events.sorted(by: { $0.event.eventID < $1.event.eventID }) {
            var remote = a.event
            remote.importedFrom = source
            guard let local = try db.event(id: remote.eventID) else {
                try db.writeEvent(remote)
                summary.events.new += 1
                continue
            }
            if local.editID == remote.editID {
                summary.events.identical += 1
                continue
            }
            let remoteChain = try db.lineage(startingAt: remote.parentEditID)
            if remoteChain.ids.contains(local.editID) {  // el remoto desciende del local
                try db.writeEvent(remote)
                summary.events.updated += 1
                continue
            }
            let localChain = try db.lineage(startingAt: local.parentEditID)
            if localChain.ids.contains(remote.editID) {  // el local es más nuevo
                summary.events.identical += 1
                continue
            }
            // Sin relación de descendencia. Cadenas completas → ramas divergentes; si falta un eslabón no se afirma divergencia.
            let resolution: ConflictResolution = remoteChain.complete && localChain.complete ? .divergent : .lineageUnknown
            try record(.event, remote.eventID, resolution, local: try JSONValue.encoding(local),
                       remote: try LingoScanArchiveWriter.eventJSON(ArchiveEvent(event: a.event, ancestors: a.ancestors)))
            summary.events.conflicted += 1
        }
    }

    // MARK: Ledger (§5.4, C4)

    private func mergeLedger() throws {
        for entry in package.content.ledger {
            var n = entry
            if entry.subjectKind == .glucose, let rid = RecordID(parsing: entry.subjectID) {
                let raw = rid.sessionID
                if translation.dropped.contains(raw) {
                    summary.rejected += 1
                    continue
                }
                let canonical = translation.canonical[raw] ?? localCanonical(of: raw) ?? raw
                // `subject_id` al canónico; `sync_identifier` intacto: es lo que ya se usó en Health (§5.1 paso 3).
                n.subjectID = RecordID.make(sessionID: canonical, analyte: rid.analyte, lifeCount: rid.lifeCount)
            }
            if try db.insertLedger(n) { summary.ledger.new += 1 } else { summary.ledger.identical += 1 }
        }
    }
}

// MARK: - Decisión pura sobre una lectura (§8.4)

struct ReadingConflict {
    var resolution: ConflictResolution
    var local: GlucoseReading?
    var remote: GlucoseReading
}

struct ReadingMergeResult {
    enum Outcome { case new, updated, identical, conflicted }
    var write: GlucoseReading?
    var conflicts: [ReadingConflict] = []
    var outcome: Outcome
}

enum ReadingMerge {
    private static func pair(_ e: Eligibility) -> [String?] { [e.status.rawValue, e.reason?.rawValue] }

    /// `remote` ya viene con la sesión canónica y `record_id` traducido.
    static func decide(local: GlucoseReading?, remote R: GlucoseReading, source: ImportedFrom,
                       policy: any ArchiveEligibilityPolicy, warmupMinutes: Int, packageSynthetic: Bool) -> ReadingMergeResult {
        func reevaluated(_ r: GlucoseReading) -> GlucoseReading {
            var n = r
            n.eligibility = policy.evaluate(raw: r.raw, lifeCount: r.lifeCount, warmupMinutes: warmupMinutes,
                                            synthetic: r.synthetic, deleted: false, inSyntheticPackage: packageSynthetic)
            n.value = policy.value(for: r.raw, eligibility: n.eligibility)
            return n
        }

        // Regla 6: no existe local → se importa y se reevalúa con la política local.
        guard let L = local else {
            var n = R
            n.importedFrom = source
            var conflicts: [ReadingConflict] = []
            if !n.deleted {
                n = reevaluated(n)
                n.importedFrom = source
                if pair(n.eligibility) != pair(R.eligibility) {
                    conflicts.append(ReadingConflict(resolution: .policyDivergence, local: nil, remote: R))
                }
            }
            return ReadingMergeResult(write: n, conflicts: conflicts, outcome: .new)
        }

        // Regla 1: tombstones pegajosos en ambos sentidos.
        if L.deleted {
            guard !R.deleted else { return ReadingMergeResult(outcome: .identical) }
            return ReadingMergeResult(conflicts: [ReadingConflict(resolution: .keptLocal, local: L, remote: R)], outcome: .conflicted)
        }
        if R.deleted {
            var n = R
            n.importedFrom = source
            n.revision = max(L.revision, R.revision) + 1
            return ReadingMergeResult(write: n, conflicts: [ReadingConflict(resolution: .tookRemote, local: L, remote: R)], outcome: .updated)
        }

        // Regla 2: sintético contra real, en cualquier sentido: el local no cambia.
        if L.synthetic != R.synthetic {
            return ReadingMergeResult(conflicts: [ReadingConflict(resolution: .keptLocal, local: L, remote: R)], outcome: .conflicted)
        }

        // Regla 3: `raw` equivalente.
        if L.raw.isEquivalent(to: R.raw) {
            var result = ReadingMergeResult(outcome: .identical)
            if L.raw == R.raw {
                // Mismos bytes: el origin pasa a ser el de mayor precedencia, sin conflicto.
                if R.origin.precedence > L.origin.precedence {
                    var n = L
                    n.origin = R.origin
                    result.write = n
                    result.outcome = .updated
                }
            } else {
                // Equivalentes pero no idénticos (observaciones complementarias): se conserva la lectura local completa
                // con su origin y la remota completa, con el suyo, en conflicts. No se combinan campos.
                result.conflicts.append(ReadingConflict(resolution: .merged, local: L, remote: R))
                result.outcome = .conflicted
            }
            if pair(L.eligibility) != pair(R.eligibility) {
                result.conflicts.append(ReadingConflict(resolution: .policyDivergence, local: L, remote: R))
                if result.outcome == .identical { result.outcome = .conflicted }
            }
            return result
        }

        // Regla 4: local excluido por una razón levantable y remoto con `raw` de otra ruta.
        if !L.eligibility.isEligible, let reason = L.eligibility.reason, reason.isLiftableByAnotherRoute, L.origin != R.origin {
            let candidate = reevaluated(R)
            if candidate.eligibility.isEligible {
                var n = candidate
                n.importedFrom = source
                n.revision = L.revision + 1
                return ReadingMergeResult(write: n, conflicts: [ReadingConflict(resolution: .merged, local: L, remote: R)], outcome: .updated)
            }
            return ReadingMergeResult(conflicts: [ReadingConflict(resolution: .keptLocal, local: L, remote: R)], outcome: .conflicted)
        }

        // Regla 5: local elegible (o sin ruta distinta) y remoto no equivalente.
        return ReadingMergeResult(conflicts: [ReadingConflict(resolution: .keptLocal, local: L, remote: R)], outcome: .conflicted)
    }
}
