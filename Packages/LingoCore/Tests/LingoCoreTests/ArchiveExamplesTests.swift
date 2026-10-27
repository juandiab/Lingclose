import Foundation
import Testing
@testable import LingoCore

@Suite("Archive · paquete válido y paquetes inválidos del contrato")
struct ArchiveExamplesTests {
    private func validPackageURL() throws -> URL {
        let url = ArchiveTestSupport.examplesURL.appending(path: "LingoScan-lingoscan-20261027T150405Z-3fa85f64.lingoscan", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: url.path), "faltan los fixtures de LingoScan_Shared/examples")
        return url
    }

    @Test("el paquete válido de examples/ se lee y valida")
    func readsValidPackage() throws {
        let package = try LingoScanArchiveReader().read(at: validPackageURL())
        #expect(package.manifest.contractVersion == "1.0.0-draft.4")
        #expect(package.manifest.synthetic)
        #expect(package.content.sessions.count == 1)
        #expect(package.content.readings.count == 163)
        #expect(package.content.events.count == 4)
        #expect(package.content.ledger.count == 96)
        #expect(package.content.conflicts.count == 1)
        // Los eventos con edición traen sus ancestros (draft.4).
        let edited = try #require(package.content.events.first { $0.event.parentEditID != nil })
        #expect(edited.ancestors?.count == 1)
    }

    @Test("importar el paquete válido tres veces deja la base idéntica a la primera")
    func importThreeTimesIsIdempotent() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path)
        let importer = ArchiveImporter(databasePath: path, now: ArchiveTestSupport.fixedNow)
        let url = try validPackageURL()

        let first = try importer.importPackage(at: url)
        #expect(!first.alreadyKnown)
        #expect(first.sessions.new == 1)
        #expect(first.readings.new == 163)
        #expect(first.events.new == 4)
        #expect(first.ledger.new == 96)
        #expect(first.rejected == 0)
        let afterFirst = try ArchiveSnapshotReader(databasePath: path).snapshot()
        let logAfterFirst = try await store.recentLogEvents().count

        for _ in 0..<2 {
            let again = try importer.importPackage(at: url)
            #expect(again.alreadyKnown)
            #expect(again.newTotal == 0 && again.updatedTotal == 0)
        }
        let afterThird = try ArchiveSnapshotReader(databasePath: path).snapshot()
        #expect(try snapshotJSON(afterFirst) == snapshotJSON(afterThird))
        #expect(try await store.recentLogEvents().count == logAfterFirst)
        #expect(try await store.readingCount() == 163)

        // Un paquete de la otra versión del conflicto, pero sin conflicto añadido por reimportar.
        #expect(try await store.conflicts().isEmpty)  // conflicts.ndjson es evidencia, no se importa
    }

    @Test("la elegibilidad se reevalúa con la política local y las lecturas llevan imported_from")
    func importedReadingsCarryProvenance() async throws {
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path)
        let summary = try ArchiveImporter(databasePath: path, now: ArchiveTestSupport.fixedNow).importPackage(at: validPackageURL())
        let session = try #require(try ArchiveSnapshotReader(databasePath: path).snapshot().sessions.first)
        #expect(session.importedFrom?.archiveID == summary.archiveID)
        let r63 = try #require(try await store.reading(recordID: "\(session.sessionID):glucose:63"))
        #expect(r63.value == 208)
        #expect(r63.raw.capped == 201 && r63.raw.uncapped == 208)
        #expect(r63.importedFrom?.archiveID == summary.archiveID)
        #expect(r63.synthetic)
        #expect(r63.eligibility.isEligible)  // paquete sintético: se evalúa como si fuera real (§6)
        let r1 = try #require(try await store.reading(recordID: "\(session.sessionID):glucose:1"))
        #expect(r1.eligibility.reason == .qualityFlag)
        // Nada sintético llega al exportador de Health.
        let all = try await store.readings(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 4_000_000_000))
        #expect(all.allSatisfy { HealthExportable(reading: $0) == nil })
    }

    @Test("los 7 paquetes de examples/invalid/ se rechazan con el motivo exacto y la base queda intacta",
          arguments: [
              ("a_hash_incorrecto", "hash_mismatch"),
              ("b_sin_manifest", "manifest_missing"),
              ("c_schema_version_2", "unsupported_schema_version"),
              ("d_linea_ndjson_invalida", "invalid_line"),
              ("e_snapshot_incompleto", "snapshot_incomplete"),
              ("g_synthetic_inconsistente", "synthetic_inconsistency"),
              ("h_sesion_sintetica_lectura_real", "synthetic_inconsistency"),
          ])
    func rejectsInvalid(caseName: String, expectedCode: String) async throws {
        let folder = ArchiveTestSupport.examplesURL.appending(path: "invalid/\(caseName)", directoryHint: .isDirectory)
        let url = try ArchiveTestSupport.packageDirectory(in: folder)
        let path = try TestSupport.temporaryDatabasePath()
        let store = try SQLiteStore(path: path)
        let importer = ArchiveImporter(databasePath: path, now: ArchiveTestSupport.fixedNow)
        do {
            _ = try importer.importPackage(at: url)
            Issue.record("\(caseName) debió rechazarse")
        } catch let e as ArchiveValidationError {
            #expect(e.code == expectedCode, "\(caseName): \(e)")
            #expect(!(e.errorDescription ?? "").isEmpty)
        }
        #expect(try await store.readingCount() == 0)
        #expect(try ArchiveSnapshotReader(databasePath: path).snapshot().sessions.isEmpty)
        #expect(try await store.isArchiveKnown(try LingoScanArchiveReader().readManifestIfPossible(url) ?? "") == false)
    }

    @Test("motivos concretos: hash del archivo, línea 4 y versión")
    func exactReasons() throws {
        func error(_ name: String) throws -> ArchiveValidationError {
            let url = try ArchiveTestSupport.packageDirectory(in: ArchiveTestSupport.examplesURL.appending(path: "invalid/\(name)", directoryHint: .isDirectory))
            do { _ = try LingoScanArchiveReader().read(at: url) } catch let e as ArchiveValidationError { return e }
            throw CocoaError(.fileReadUnknown)
        }
        guard case .hashMismatch(let file, _, _) = try error("a_hash_incorrecto") else { Issue.record("a_"); return }
        #expect(file == "readings.ndjson")
        guard case .invalidLine(let f, let line, _) = try error("d_linea_ndjson_invalida") else { Issue.record("d_"); return }
        #expect(f == "readings.ndjson" && line == 4)
        guard case .unsupportedSchemaVersion(let found, let supported) = try error("c_schema_version_2") else { Issue.record("c_"); return }
        #expect(found == 2 && supported == 1)
    }

    @Test("una carpeta .partial se ignora: ni paquete ni error")
    func partialIsIgnored() throws {
        let folder = ArchiveTestSupport.examplesURL.appending(path: "invalid/f_partial_vacia_ignorar", directoryHint: .isDirectory)
        let path = try TestSupport.temporaryDatabasePath()
        _ = try SQLiteStoreBootstrap.open(path)
        let outcomes = ArchiveImporter(databasePath: path).importAll(in: folder)
        #expect(outcomes.isEmpty)
        let partial = folder.appending(path: "LingoScan-lingoscan-20261027T160500Z-ffffffff.lingoscan.partial", directoryHint: .isDirectory)
        do { _ = try LingoScanArchiveReader().readManifest(at: partial); Issue.record("debió ser partial") } catch let e as ArchiveValidationError {
            #expect(e == .partialPackage)
        }
    }

    @Test("importAll recorre una carpeta: importa lo válido, rechaza lo inválido y omite lo conocido")
    func importAllOverFolder() throws {
        let folder = try ArchiveTestSupport.temporaryDirectory("destino")
        let fm = FileManager.default
        let valid = try validPackageURL()
        try fm.copyItem(at: valid, to: folder.appending(path: valid.lastPathComponent, directoryHint: .isDirectory))
        let bad = try ArchiveTestSupport.packageDirectory(in: ArchiveTestSupport.examplesURL.appending(path: "invalid/a_hash_incorrecto", directoryHint: .isDirectory))
        try fm.copyItem(at: bad, to: folder.appending(path: bad.lastPathComponent, directoryHint: .isDirectory))
        try fm.createDirectory(at: folder.appending(path: "LingoScan-lingoscan-20261027T160500Z-ffffffff.lingoscan.partial"), withIntermediateDirectories: false)
        let path = try TestSupport.temporaryDatabasePath()
        _ = try SQLiteStoreBootstrap.open(path)
        let importer = ArchiveImporter(databasePath: path, now: ArchiveTestSupport.fixedNow)
        let first = importer.importAll(in: folder)
        #expect(first.count == 2)
        var imported = 0, rejected = 0
        for o in first {
            switch o {
            case .imported: imported += 1
            case .rejected(_, _, let code): rejected += 1; #expect(code == "hash_mismatch")
            case .skipped: Issue.record("nada estaba importado")
            }
        }
        #expect(imported == 1 && rejected == 1)
        let second = importer.importAll(in: folder)
        #expect(second.contains { if case .skipped = $0 { true } else { false } })
    }

    func snapshotJSON(_ c: ArchiveContent) throws -> String {
        let encoder = NDJSON.makeEncoder()
        let v = JSONValue.object([
            "sessions": .array(try c.sessions.sorted { $0.sessionID < $1.sessionID }.map { try JSONValue.encoding($0) }),
            "readings": .array(try c.readings.map { try JSONValue.encoding($0) }),
            "events": .array(try c.events.sorted { $0.event.eventID < $1.event.eventID }.map { try LingoScanArchiveWriter.eventJSON($0) }),
            "ledger": .array(try c.ledger.sorted { $0.attemptID < $1.attemptID }.map { try JSONValue.encoding($0) }),
            "conflicts": .array(try c.conflicts.map { try JSONValue.encoding($0) }),
        ])
        return String(decoding: try encoder.encode(v), as: UTF8.self)
    }
}

/// Crea el esquema de una base vacía sin guardar la referencia al almacén.
enum SQLiteStoreBootstrap {
    static func open(_ path: String) throws -> SQLiteStore { try SQLiteStore(path: path) }
}

extension LingoScanArchiveReader {
    /// `archive_id` del manifest si se puede leer (solo para comprobaciones de pruebas).
    func readManifestIfPossible(_ url: URL) throws -> String? {
        try? readManifest(at: url).manifest.archiveID
    }
}
