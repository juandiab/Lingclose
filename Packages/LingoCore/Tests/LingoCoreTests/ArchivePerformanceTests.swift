import Foundation
import Testing
@testable import LingoCore

/// Un sensor de 14 días son ~20 000 lecturas: exportar, validar e importar deben seguir siendo cuestión de segundos.
@Suite("Archive · rendimiento")
struct ArchivePerformanceTests {
    @Test("14 días (20 160 lecturas): exportar, leer y validar, e importar")
    func fourteenDaysRoundTrip() async throws {
        let pathA = try TestSupport.temporaryDatabasePath("a")
        let storeA = try SQLiteStore(path: pathA, now: ArchiveTestSupport.fixedNow)
        let session = TestSupport.session()
        try await storeA.upsertSession(session)
        let readings = (1...20_160).map { lc in
            TestSupport.reading(session, lc: lc, raw: RawReading(capped: 90 + lc % 50, uncapped: 92 + lc % 50, historicLifeCount: max(lc - 18, 0), rateCenti: 3, trend: 3,
                                                                  actionable: false, temperatureCenti: 3200, rangeBits: 0, qualityFlag: lc < 4, channel: 1,
                                                                  reservedHex: "00112233445566778899aabbccddeeff"), origin: .live)
        }
        try await storeA.insertReadings(readings)

        let clock = ContinuousClock()
        let dest = try ArchiveTestSupport.temporaryDirectory()
        let exporter = ArchiveExporter(store: storeA, databasePath: pathA, writer: LingoScanArchiveWriter(producer: ArchiveTestSupport.producer), now: ArchiveTestSupport.fixedNow)
        var result: ArchiveExportResult?
        let exportTime = try await clock.measure { result = try await exporter.export(to: dest) }
        let exported = try #require(result)
        #expect(exported.verified)

        let pathB = try TestSupport.temporaryDatabasePath("b")
        _ = try SQLiteStore(path: pathB)
        var summary: ImportSummary?
        let importTime = try clock.measure { summary = try ArchiveImporter(databasePath: pathB, now: ArchiveTestSupport.fixedNow).importPackage(at: exported.url) }
        #expect(summary?.readings.new == 20_160)
        Swift.print("T-10 rendimiento (debug): exportar+validar \(exportTime), importar \(importTime), tamaño NDJSON \(try Data(contentsOf: exported.url.appending(path: "readings.ndjson")).count / 1024) KiB")
        #expect(exportTime < .seconds(60) && importTime < .seconds(60))
    }
}
