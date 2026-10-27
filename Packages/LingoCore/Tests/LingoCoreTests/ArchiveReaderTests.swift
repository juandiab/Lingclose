import Foundation
import Testing
@testable import LingoCore

/// Validación estricta del lector (contrato §8.2–§8.3) sobre variantes del paquete válido de `examples/`.
@Suite("Archive · validación del lector")
struct ArchiveReaderTests {
    static let validName = "LingoScan-lingoscan-20261027T150405Z-3fa85f64.lingoscan"

    /// Copia el paquete válido a un directorio temporal y devuelve su ruta.
    static func copyOfValid() throws -> URL {
        let src = ArchiveTestSupport.examplesURL.appending(path: validName, directoryHint: .isDirectory)
        let dst = try ArchiveTestSupport.temporaryDirectory().appending(path: validName, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }

    /// Reescribe un archivo del paquete y deja el manifest coherente (bytes, SHA-256 y, si se pide, `records`).
    static func rewrite(_ pkg: URL, file: String, records: Int? = nil, _ transform: (Data) throws -> Data) throws {
        let fileURL = pkg.appending(path: file)
        let data = try transform(Data(contentsOf: fileURL))
        try data.write(to: fileURL)
        try editManifest(pkg) { m in
            var files = m["files"] as? [[String: Any]] ?? []
            for i in files.indices where files[i]["name"] as? String == file {
                files[i]["bytes"] = data.count
                files[i]["sha256"] = ArchiveHashing.sha256Hex(data)
                if let records { files[i]["records"] = records }
            }
            m["files"] = files
        }
    }

    static func editManifest(_ pkg: URL, _ edit: (inout [String: Any]) -> Void) throws {
        let url = pkg.appending(path: "manifest.json")
        var m = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        edit(&m)
        try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]).write(to: url)
    }

    static func expectFailure(_ pkg: URL, _ matches: (ArchiveValidationError) -> Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            _ = try LingoScanArchiveReader().read(at: pkg)
            Issue.record("debió rechazarse", sourceLocation: sourceLocation)
        } catch let e as ArchiveValidationError {
            #expect(matches(e), "motivo inesperado: \(e)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("error inesperado \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test("el paquete copiado sin cambios sigue siendo válido")
    func untouchedCopyIsValid() throws {
        let p = try LingoScanArchiveReader().read(at: Self.copyOfValid())
        #expect(p.warnings.isEmpty)
    }

    @Test("claves prohibidas en una sesión (secretos) rechazan el paquete", arguments: ["mac", "pin_hex", "k_auth_hex", "receiver_id", "sensor_serial", "ble", "auth", "sensor_certificate_hex", "patch_info_hex"])
    func forbiddenSessionKeys(key: String) throws {
        let pkg = try Self.copyOfValid()
        try Self.rewrite(pkg, file: "sessions.json") { d in
            var o = try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any])
            var s = try #require(o["sessions"] as? [[String: Any]])
            s[0][key] = "AA:BB"
            o["sessions"] = s
            return try JSONSerialization.data(withJSONObject: o)
        }
        Self.expectFailure(pkg) { $0 == .forbiddenSessionKey(key) }
    }

    @Test("contract_version de otro major, snapshot parcial sin from_utc y nombre que no coincide")
    func manifestRules() throws {
        let major = try Self.copyOfValid()
        try Self.editManifest(major) { $0["contract_version"] = "2.0.0" }
        Self.expectFailure(major) { if case .unsupportedContractVersion = $0 { true } else { false } }

        let draft = try Self.copyOfValid()
        try Self.editManifest(draft) { $0["contract_version"] = "1.4.2" }  // minor mayor: se acepta
        #expect((try? LingoScanArchiveReader().read(at: draft)) != nil)

        let partial = try Self.copyOfValid()
        try Self.editManifest(partial) { m in var s = m["snapshot"] as! [String: Any]; s["kind"] = "partial"; m["snapshot"] = s }
        Self.expectFailure(partial) { if case .manifestInvalid = $0 { true } else { false } }

        let renamed = try Self.copyOfValid()
        let other = renamed.deletingLastPathComponent().appending(path: "LingoScan-lingoscan-20261027T150405Z-3fa85f65.lingoscan", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: renamed, to: other)
        Self.expectFailure(other) { if case .nameMismatch = $0 { true } else { false } }

        let notPackage = try ArchiveTestSupport.temporaryDirectory().appending(path: "cualquier-cosa", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: notPackage, withIntermediateDirectories: true)
        Self.expectFailure(notPackage) { if case .notAPackage = $0 { true } else { false } }
    }

    @Test("files[]: nombres con ruta, archivo obligatorio no listado, archivo listado ausente y archivos extra")
    func filesRules() throws {
        let traversal = try Self.copyOfValid()
        try Self.editManifest(traversal) { m in var f = m["files"] as! [[String: Any]]; f[0]["name"] = "../sessions.json"; m["files"] = f }
        Self.expectFailure(traversal) { if case .invalidFileName = $0 { true } else { false } }

        let unlisted = try Self.copyOfValid()
        try Self.editManifest(unlisted) { m in m["files"] = (m["files"] as! [[String: Any]]).filter { $0["name"] as? String != "events.ndjson" } }
        Self.expectFailure(unlisted) { $0 == .mandatoryFileNotListed("events.ndjson") }

        let missing = try Self.copyOfValid()
        try FileManager.default.removeItem(at: missing.appending(path: "readings.csv"))
        Self.expectFailure(missing) { $0 == .fileMissing("readings.csv") }

        let extra = try Self.copyOfValid()
        try Data("x".utf8).write(to: extra.appending(path: "notas.txt"))
        let p = try LingoScanArchiveReader().read(at: extra)
        #expect(p.warnings.count == 1 && p.warnings[0].contains("notas.txt"), "archivo presente y no listado: aviso y se ignora")
    }

    @Test("registros: campo obligatorio ausente, valor en lectura excluida, duplicados, sesión inexistente y BOM")
    func recordRules() throws {
        func mutateLines(_ transform: @escaping (inout [[String: Any]]) -> Void) throws -> URL {
            let pkg = try Self.copyOfValid()
            try Self.rewrite(pkg, file: "readings.ndjson") { d in
                var rows = try String(decoding: d, as: UTF8.self).split(separator: "\n").map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
                transform(&rows)
                return try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) + "\n" }.joined().data(using: .utf8)!
            }
            return pkg
        }
        let missingKey = try mutateLines { rows in var raw = rows[0]["raw"] as! [String: Any]; raw.removeValue(forKey: "quality_flag"); rows[0]["raw"] = raw }
        Self.expectFailure(missingKey) { if case .invalidLine(_, 1, let d) = $0 { d.contains("quality_flag") } else { false } }

        let valueOnExcluded = try mutateLines { rows in rows[0]["value"] = 100 }
        Self.expectFailure(valueOnExcluded) { if case .invalidLine(_, 1, _) = $0 { true } else { false } }

        let duplicate = try mutateLines { rows in rows.append(rows[0]) }
        Self.expectFailure(duplicate) { if case .invalidRecord(_, let d) = $0 { d.contains("duplicado") } else { false } }

        let orphan = try mutateLines { rows in
            let other = "11111111-1111-4111-8111-111111111111"
            rows[0]["session_id"] = other
            rows[0]["record_id"] = "\(other):glucose:1"
        }
        Self.expectFailure(orphan) { if case .invalidRecord(_, let d) = $0 { d.contains("no existe en sessions.json") } else { false } }

        let badTZ = try mutateLines { rows in rows[0]["tz_at_capture"] = "no es zona" }
        Self.expectFailure(badTZ) { if case .invalidLine(_, 1, _) = $0 { true } else { false } }

        let bom = try Self.copyOfValid()
        try Self.rewrite(bom, file: "events.ndjson") { Data([0xEF, 0xBB, 0xBF]) + $0 }
        Self.expectFailure(bom) { if case .invalidFile(let f, _) = $0 { f == "events.ndjson" } else { false } }

        let blankLine = try Self.copyOfValid()
        try Self.rewrite(blankLine, file: "health_export_ledger.ndjson") { var d = $0; d.insert(contentsOf: Data("\n".utf8), at: 0); return d }
        Self.expectFailure(blankLine) { if case .invalidLine(_, 1, let d) = $0 { d.contains("vacía") } else { false } }

        let nan = try Self.copyOfValid()
        try Self.rewrite(nan, file: "events.ndjson") { Data(String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "\"carbs_g\":45", with: "\"carbs_g\":NaN").utf8) }
        Self.expectFailure(nan) { if case .invalidLine = $0 { true } else { false } }
    }

    @Test("edit_ancestors: la cadena debe ser continua y llegar a la creación")
    func ancestorRules() throws {
        let pkg = try Self.copyOfValid()
        try Self.rewrite(pkg, file: "events.ndjson") { d in
            Data(String(decoding: d, as: UTF8.self)
                .replacingOccurrences(of: "\"edit_ancestors\":[{\"edit_id\":\"50b1b1e0-3878-4ff5-bff6-cd07877edd05\",\"parent_edit_id\":null}]",
                                      with: "\"edit_ancestors\":[{\"edit_id\":\"50b1b1e0-3878-4ff5-bff6-cd07877edd05\",\"parent_edit_id\":\"2c2f461d-f01f-4f12-8af2-f3c0f21d54a7\"}]").utf8)
        }
        Self.expectFailure(pkg) { if case .invalidLine(_, _, let d) = $0 { d.contains("edit_ancestors") } else { false } }
    }

    @Test("conteos y CSV: counts del manifest, records y cabecera de readings.csv")
    func countsAndCSV() throws {
        let counts = try Self.copyOfValid()
        try Self.editManifest(counts) { m in var c = m["counts"] as! [String: Any]; c["readings"] = 999; m["counts"] = c }
        Self.expectFailure(counts) { if case .countMismatch = $0 { true } else { false } }

        let records = try Self.copyOfValid()
        try Self.editManifest(records) { m in var f = m["files"] as! [[String: Any]]; f[1]["records"] = 5; m["files"] = f }
        Self.expectFailure(records) { if case .countMismatch = $0 { true } else { false } }

        let csv = try Self.copyOfValid()
        try Self.rewrite(csv, file: "readings.csv") { Data(String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "record_id,session_id", with: "id,session_id").utf8) }
        Self.expectFailure(csv) { if case .invalidFile(let f, _) = $0 { f == "readings.csv" } else { false } }
    }

    @Test("NDJSON.lines y nombres de paquete")
    func lowLevel() throws {
        #expect(try NDJSON.lines(of: Data("{}\n{}\n".utf8), file: "x").map(\.number) == [1, 2])
        #expect(try NDJSON.lines(of: Data("{}\n{}".utf8), file: "x").count == 2)
        #expect(try NDJSON.lines(of: Data(), file: "x").isEmpty)
        #expect(throws: ArchiveValidationError.self) { try NDJSON.lines(of: Data("{}\r\n".utf8), file: "x") }
        let name = ArchivePackageName(parsing: "LingoScan-astra-20261027T143000Z-3d948f93.lingoscan")
        #expect(name?.producerTag == "astra" && name?.archiveID8 == "3d948f93" && name?.createdAt.rfc3339 == "2026-10-27T14:30:00Z")
        #expect(name?.folderName == "LingoScan-astra-20261027T143000Z-3d948f93.lingoscan")
        #expect(ArchivePackageName(parsing: "LingoScan-Astra-20261027T143000Z-3d948f93.lingoscan") == nil)
        #expect(ArchivePackageName(parsing: "LingoScan-astra-20261027T143000Z-3d948f9.lingoscan") == nil)
        #expect(ArchivePackageName(parsing: "LingoScan-astra-20261027T143000Z-3d948f93.lingoscan.partial") == nil)
        #expect(ArchiveManifest.major(ofContractVersion: "1.0.0-draft.4") == 1)
        #expect(ArchiveManifest.major(ofContractVersion: "2.0.0") == 2)
        #expect(ArchiveManifest.major(ofContractVersion: "1.0") == nil)
        #expect(ArchiveManifest.major(ofContractVersion: "01.0.0") == nil)
        #expect(CSVWriter.localTime(UTCInstant(epochSeconds: 1_793_102_460), timeZoneIdentifier: "America/Bogota") == "2026-10-27T07:01:00-05:00")
        #expect(CSVWriter.localTime(UTCInstant(epochSeconds: 1_793_102_460), timeZoneIdentifier: "Asia/Kolkata") == "2026-10-27T17:31:00+05:30")
    }
}
