import Foundation
@testable import LingoCore

/// Soporte de las pruebas de paquetes `.lingoscan`: ubicación de los fixtures compartidos y una política `astra-v1`
/// (rango 39...600) para ejercitar, con el mismo importador, el lado de la otra app.
enum ArchiveTestSupport {
    /// `LingoScan_Shared/` (hermana de `LingoScan_Claude/`), calculada desde la ruta de este archivo.
    static var sharedURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }  // LingoCoreTests, Tests, LingoCore, Packages, LingoScan_Claude, LingoScan
        return url.appending(path: "LingoScan_Shared", directoryHint: .isDirectory)
    }

    static var examplesURL: URL { sharedURL.appending(path: "examples", directoryHint: .isDirectory) }

    static func packageDirectory(in folder: URL) throws -> URL {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".lingoscan") && !$0.hasSuffix(".partial") }
        guard let name = names.first, names.count == 1 else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: folder.path])
        }
        return folder.appending(path: name, directoryHint: .isDirectory)
    }

    static func temporaryDirectory(_ name: String = "dir") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoCoreArchive-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_793_200_000) }

    static let producer = ArchiveProducerInfo.lingoScan(appVersion: "0.1.0", build: "1", deviceModel: "iPhone18,2", osVersion: "27.0")

    /// Siembra la base con el paquete **propio** del dueño, sin fusión: lo que esa app ya tenía antes de importar.
    static func seed(_ store: SQLiteStore, with package: ArchivePackage) async throws {
        for s in package.content.sessions { try await store.upsertSession(s) }
        for r in package.content.readings { try await store.insertReading(r) }
        for e in package.content.events { try await store.upsertEvent(e.event, ancestors: e.ancestors ?? []) }
        for l in package.content.ledger { try await store.appendLedger(l) }
        try await store.recordArchive(ArchiveRecord(
            archiveID: package.manifest.archiveID, createdAt: package.manifest.createdAt, path: package.url.path,
            readings: package.content.readings.count, manifestSHA256: package.manifestSHA256, verified: true))
    }
}

/// `astra-v1` de los fixtures: igual que `lingoscan-v1` pero con rango 39...600.
struct AstraV1TestPolicy: ArchiveEligibilityPolicy {
    var policyID: String { "astra-v1" }
    var policyVersion: String { "1.0.0" }

    func evaluate(raw: RawReading, lifeCount: Int, warmupMinutes: Int, synthetic: Bool, deleted: Bool,
                  inSyntheticPackage: Bool) -> Eligibility {
        if deleted { return .excluded(.deleted, policyID: policyID, policyVersion: policyVersion) }
        if synthetic && !inSyntheticPackage { return .excluded(.synthetic, policyID: policyID, policyVersion: policyVersion) }
        if raw.qualityFlag { return .excluded(.qualityFlag, policyID: policyID, policyVersion: policyVersion) }
        if lifeCount < warmupMinutes { return .excluded(.warmUp, policyID: policyID, policyVersion: policyVersion) }
        guard let v = raw.uncapped ?? raw.capped else { return .excluded(.decoderError, policyID: policyID, policyVersion: policyVersion) }
        if !(39...600).contains(v) { return .excluded(.outOfRange, policyID: policyID, policyVersion: policyVersion) }
        return .eligible(policyID: policyID, policyVersion: policyVersion)
    }

    func value(for raw: RawReading, eligibility: Eligibility) -> Int? {
        eligibility.isEligible ? (raw.uncapped ?? raw.capped) : nil
    }
}

extension JSONValue {
    /// Navega por una ruta con puntos (`eligibility.reason`, `imported_from.archive_id`).
    func value(at path: String) -> JSONValue? {
        var current: JSONValue? = self
        for part in path.split(separator: ".") {
            guard case .object(let o)? = current else { return nil }
            current = o[String(part)] ?? JSONValue.null
            if o[String(part)] == nil { return JSONValue.null }
        }
        return current
    }
}
