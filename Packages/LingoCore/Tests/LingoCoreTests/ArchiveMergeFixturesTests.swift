import Foundation
import Testing
@testable import LingoCore

/// Fixtures `LingoScan_Shared/examples/merge/<caso>/` (draft.4): para cada caso y cada "dueño" (la app cuya base se
/// siembra con su propio paquete) se importan los demás en todos los órdenes, repetidos y con el paquete propio al
/// final; todas las secuencias deben dar la misma base y coincidir con `expected.json`.
@Suite("Archive · fusión contra examples/merge")
struct ArchiveMergeFixturesTests {
    static let cases = ["alias", "events", "exclusions", "ledger", "out_of_order", "synthetic"]

    struct Fixture {
        let name: String
        let expected: JSONValue
        let packages: [String: ArchivePackage]  // por nombre de carpeta
        let owners: [(tag: String, folder: String)]

        init(case name: String) throws {
            self.name = name
            let dir = ArchiveTestSupport.examplesURL.appending(path: "merge/\(name)", directoryHint: .isDirectory)
            let data = try Data(contentsOf: dir.appending(path: "expected.json"))
            expected = try JSONDecoder().decode(JSONValue.self, from: data)
            var pk: [String: ArchivePackage] = [:]
            guard case .array(let list)? = expected.value(at: "packages") else { throw CocoaError(.fileReadCorruptFile) }
            for p in list {
                guard case .string(let n)? = p.value(at: "name") else { continue }
                pk[n] = try LingoScanArchiveReader().read(at: dir.appending(path: n, directoryHint: .isDirectory))
            }
            packages = pk
            guard case .object(let o)? = expected.value(at: "owners") else { throw CocoaError(.fileReadCorruptFile) }
            owners = o.compactMap { k, v in if case .string(let s) = v { (k, s) } else { nil } }.sorted { $0.0 < $1.0 }
        }
    }

    static func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[T]] in
            var rest = items
            let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    /// Estado normalizado de una base, para comparar secuencias de importación.
    static func normalized(_ c: ArchiveContent) throws -> String {
        let v = JSONValue.object([
            "sessions": .array(try c.sessions.sorted { $0.sessionID < $1.sessionID }.map { try JSONValue.encoding($0) }),
            "readings": .array(try c.readings.map { try JSONValue.encoding($0) }),
            "events": .array(try c.events.sorted { $0.event.eventID < $1.event.eventID }.map { try LingoScanArchiveWriter.eventJSON($0) }),
            "ledger": .array(try c.ledger.sorted { $0.attemptID < $1.attemptID }.map { try JSONValue.encoding($0) }),
            "conflicts": .array(try c.conflicts.map { try JSONValue.encoding($0) }),
        ])
        return String(decoding: try NDJSON.makeEncoder().encode(v), as: UTF8.self)
    }

    @Test("cada caso: todas las secuencias de importación convergen y coinciden con expected.json", arguments: cases)
    func caseMatchesExpected(caseName: String) async throws {
        let fixture = try Fixture(case: caseName)
        var mismatches: [String] = []
        for (tag, ownFolder) in fixture.owners {
            let own = try #require(fixture.packages[ownFolder])
            let others = fixture.packages.filter { $0.key != ownFolder }.sorted { $0.key < $1.key }.map(\.value)
            let policy: any ArchiveEligibilityPolicy = tag == "astra" ? AstraV1TestPolicy() : LingoScanV1ArchivePolicy()
            var results: [String: [String]] = [:]
            var reference: ArchiveContent?
            for perm in Self.permutations(others) {
                for (label, sequence) in [("orden", perm), ("repetido", perm + perm), ("con propio al final", perm + [own])] {
                    let path = try TestSupport.temporaryDatabasePath()
                    let store = try SQLiteStore(path: path)
                    try await ArchiveTestSupport.seed(store, with: own)
                    let importer = ArchiveImporter(databasePath: path, localPolicy: policy, now: ArchiveTestSupport.fixedNow)
                    for p in sequence { _ = try importer.importPackage(at: p.url) }
                    let content = try ArchiveSnapshotReader(databasePath: path).snapshot()
                    if reference == nil { reference = content }
                    let ids = sequence.map { String($0.manifest.archiveID.prefix(4)) }.joined(separator: ",")
                    results[try Self.normalized(content), default: []].append("\(label) \(ids)")
                }
            }
            if results.count != 1 { mismatches.append("[\(tag)] las secuencias NO convergen: \(results.values.map { $0.joined(separator: ";") })") }
            let final = try #require(reference)
            let expectedOwner = try #require(fixture.expected.value(at: "result_by_owner.\(tag)"))
            let handover = fixture.packages.values.compactMap(\.manifest.health.handoverAt).max()
            mismatches += Self.check(final, expected: expectedOwner, packages: Array(fixture.packages.values), handover: handover)
                .map { "[\(tag)] \($0)" }
        }
        #expect(mismatches.isEmpty, "\(caseName): \(mismatches.joined(separator: " | "))")
    }

    /// Compara una base con `result_by_owner[dueño]`. Devuelve las diferencias.
    static func check(_ db: ArchiveContent, expected exp: JSONValue, packages: [ArchivePackage], handover: UTCInstant?) -> [String] {
        var errs: [String] = []
        func eq<T: Equatable>(_ what: String, _ got: T, _ want: T) { if got != want { errs.append("\(what): obtenido \(got), esperado \(want)") } }
        func int(_ path: String) -> Int? { if case .int(let i)? = exp.value(at: path) { Int(i) } else { nil } }

        eq("sessions", db.sessions.count, int("counts.sessions") ?? -1)
        eq("readings", db.readings.count, int("counts.readings") ?? -1)
        eq("events", db.events.count, int("counts.events") ?? -1)
        eq("ledger_entries", db.ledger.count, int("counts.ledger_entries") ?? -1)
        eq("conflicts", db.conflicts.count, int("counts.conflicts") ?? -1)

        func triples(_ list: [(String, String, String)]) -> [String] { list.map { "\($0.0)|\($0.1)|\($0.2)" }.sorted() }
        if case .array(let want)? = exp.value(at: "conflicts") {
            let wantTriples = want.compactMap { c -> (String, String, String)? in
                guard case .string(let k)? = c.value(at: "kind"), case .string(let i)? = c.value(at: "id"),
                      case .string(let r)? = c.value(at: "resolution") else { return nil }
                return (k, i, r)
            }
            eq("conflictos (kind,id,resolution)", triples(db.conflicts.map { ($0.kind.rawValue, $0.id, $0.resolution.rawValue) }), triples(wantTriples))
        }
        if case .array(let want)? = exp.value(at: "sessions") {
            eq("session_ids", db.sessions.map(\.sessionID).sorted(),
               want.compactMap { if case .string(let s)? = $0.value(at: "session_id") { s } else { nil } }.sorted())
            for es in want {
                guard case .string(let id)? = es.value(at: "session_id"), let s = db.sessions.first(where: { $0.sessionID == id }) else { continue }
                if case .array(let aliases)? = es.value(at: "aliases") {
                    eq("aliases de \(id.prefix(8))", s.aliases.map(\.sessionID).sorted(),
                       aliases.compactMap { if case .string(let a) = $0 { a } else { nil } }.sorted())
                }
                if case .bool(let b)? = es.value(at: "synthetic") { eq("synthetic de sesión \(id.prefix(8))", s.synthetic, b) }
                if case .array(let details)? = es.value(at: "alias_details") {
                    for d in details {
                        guard case .string(let aid)? = d.value(at: "session_id"), let a = s.aliases.first(where: { $0.sessionID == aid }) else {
                            errs.append("alias_details: falta alias"); continue
                        }
                        if case .string(let app)? = d.value(at: "app_id") { eq("alias app_id", a.appID, app) }
                        if case .string(let ar)? = d.value(at: "archive_id") { eq("alias archive_id", a.archiveID, ar) }
                    }
                }
            }
        }
        if case .object(let readings)? = exp.value(at: "readings") {
            for (rid, fields) in readings {
                guard let r = db.readings.first(where: { $0.recordID == rid }), let json = try? JSONValue.encoding(r) else {
                    errs.append("lectura \(rid.suffix(12)) ausente"); continue
                }
                guard case .object(let fs) = fields else { continue }
                for (path, want) in fs where json.value(at: path) != want {
                    errs.append("lectura \(rid.suffix(12)) \(path): obtenido \(String(describing: json.value(at: path))), esperado \(want)")
                }
            }
        }
        if case .object(let events)? = exp.value(at: "events") {
            for (eid, fields) in events {
                guard let e = db.events.first(where: { $0.event.eventID == eid }), let json = try? JSONValue.encoding(e.event) else {
                    errs.append("evento \(eid.prefix(8)) ausente"); continue
                }
                guard case .object(let fs) = fields else { continue }
                for (path, want) in fs where json.value(at: path) != want {
                    errs.append("evento \(eid.prefix(8)) \(path): obtenido \(String(describing: json.value(at: path))), esperado \(want)")
                }
            }
        }
        if case .array(let preserved)? = exp.value(at: "preserved_edit_ids") {
            var have = Set(db.events.map(\.event.editID))
            for c in db.conflicts where c.kind == .event {
                if case .string(let id)? = c.remote?.value(at: "edit_id") { have.insert(id) }
            }
            let missing = preserved.compactMap { if case .string(let s) = $0 { s } else { nil } }.filter { !have.contains($0) }
            eq("ediciones perdidas (ni en events ni en conflicts.remote)", missing, [])
        }
        if case .object(let ledger)? = exp.value(at: "ledger") {
            errs += checkLedger(db, expected: ledger, handover: handover)
        }
        if case .object(let inv)? = exp.value(at: "invariants") {
            if inv["no_duplicate_keys"] == .bool(true) {
                eq("record_id únicos", Set(db.readings.map(\.recordID)).count, db.readings.count)
                let incoherent = db.readings.filter { $0.recordID != RecordID.make(sessionID: $0.sessionID, analyte: $0.analyte, lifeCount: $0.lifeCount) }
                eq("record_id coherente con (sesión canónica, analito, lc)", incoherent.count, 0)
            }
            if inv["no_orphan_references"] == .bool(true) {
                let ids = Set(db.sessions.map(\.sessionID))
                eq("lecturas huérfanas", db.readings.filter { !ids.contains($0.sessionID) }.count, 0)
                eq("ledger huérfano", db.ledger.filter { $0.subjectKind == .glucose && !ids.contains(RecordID(parsing: $0.subjectID)?.sessionID ?? "") }.count, 0)
            }
            if inv["all_synthetic"] == .bool(true) {
                eq("registros con synthetic:false",
                   db.readings.filter { !$0.synthetic }.count + db.events.filter { !$0.event.synthetic }.count + db.sessions.filter { !$0.synthetic }.count, 0)
            }
            if case .int(let n)? = inv["health_exportable"] {
                let sessions = Dictionary(uniqueKeysWithValues: db.sessions.map { ($0.sessionID, $0) })
                let count = db.readings.filter { r in sessions[r.sessionID].flatMap { HealthExportable(reading: r, session: $0) } != nil }.count
                eq("registros que llegarían al exportador de Health", count, Int(n))
            }
        }
        return errs
    }

    static func checkLedger(_ db: ArchiveContent, expected: [String: JSONValue], handover: UTCInstant?) -> [String] {
        var errs: [String] = []
        func eq<T: Equatable>(_ what: String, _ got: T, _ want: T) { if got != want { errs.append("ledger.\(what): obtenido \(got), esperado \(want)") } }
        let best = ArchiveHealthDerivation.bestStates(db.ledger)
        let pending = ArchiveHealthDerivation.pendingSubjects(readings: db.readings, events: [], ledger: db.ledger)
        func strings(_ v: JSONValue?) -> [String] { if case .array(let a)? = v { a.compactMap { if case .string(let s) = $0 { s } else { nil } } } else { [] } }
        for (k, want) in expected {
            switch k {
            case "derived_states":
                guard case .object(let o) = want else { continue }
                for (subject, state) in o {
                    eq("estado \(subject.suffix(4))", (best[subject] ?? .none).rawValue, { if case .string(let s) = state { s } else { "" } }())
                }
            case "pending_subjects": if case .int(let n) = want { eq(k, pending.count, Int(n)) }
            case "pending_ids": eq(k, pending.map(\.subjectID).sorted(), strings(want).sorted())
            case "holes_before_handover":
                eq(k, pending.filter { handover != nil && $0.measuredAt <= handover! }.map(\.subjectID).sorted(), strings(want).sorted())
            case "auto_write_after_handover":
                eq(k, pending.filter { handover != nil && $0.measuredAt > handover! }.map(\.subjectID).sorted(), strings(want).sorted())
            case "needs_reconcile": eq(k, pending.filter { best[$0.subjectID] == .unknown }.map(\.subjectID).sorted(), strings(want).sorted())
            case "handover_at_utc":
                if case .string(let s) = want { eq(k, handover?.rfc3339, s) }
            case "last_confirmed_by_writer":
                guard case .object(let o) = want else { continue }
                for (writer, when) in o {
                    guard case .string(let s) = when else { continue }
                    eq("last_confirmed \(writer)", ArchiveHealthDerivation.lastConfirmed(writerAppID: writer, readings: db.readings, ledger: db.ledger)?.rfc3339, s)
                }
            case "samples":
                guard case .object(let o) = want else { continue }
                for (attempt, fields) in o {
                    guard let entry = db.ledger.first(where: { $0.attemptID == attempt }), let json = try? JSONValue.encoding(entry),
                          case .object(let fs) = fields else { errs.append("ledger.samples: falta \(attempt.prefix(8))"); continue }
                    for (path, v) in fs where json.value(at: path) != v { errs.append("ledger.\(attempt.prefix(8)).\(path): obtenido \(String(describing: json.value(at: path))), esperado \(v)") }
                }
            default: break
            }
        }
        return errs
    }
}
