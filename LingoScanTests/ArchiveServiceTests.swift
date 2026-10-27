import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// Almacén de bookmark en memoria, para no tocar `UserDefaults` en pruebas.
final class InMemoryBookmarkStore: FolderBookmarkStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    init(_ data: Data? = nil) { self.data = data }
    func load() -> Data? { lock.withLock { data } }
    func save(_ data: Data?) { lock.withLock { self.data = data } }
}

@MainActor
struct ArchiveServiceTests {
    static let activation: Int64 = 1_793_102_400
    static let sharedExamples: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // archivo, LingoScanTests, LingoScan_Claude
        return url.appending(path: "LingoScan_Shared/examples", directoryHint: .isDirectory)
    }()

    struct Harness {
        let service: ArchiveService
        let store: SQLiteStore
        let path: String
        let fallback: URL
        let bookmarks: InMemoryBookmarkStore
        let clock: Clock
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
    }

    static func tempDir(_ name: String = "dir") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "t10-\(UUID().uuidString)/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Servicio con base propia con una sesión de 3 h y un contenedor "iCloud" falso en un directorio temporal.
    static func makeHarness(populate: Bool = true, bookmark: Data? = nil) async throws -> Harness {
        let dir = try tempDir("db")
        let path = dir.appending(path: "lingoscan.sqlite").path(percentEncoded: false)
        let clock = Clock(Date(timeIntervalSince1970: Double(activation) + 20_000))
        let store = try SQLiteStore(path: path, now: { clock.now })
        if populate { try await seed(store) }
        let fallback = try tempDir("icloud-documents")
        let bookmarks = InMemoryBookmarkStore(bookmark)
        let service = ArchiveService(
            store: store, databasePath: path, bookmarks: bookmarks, fallbackContainer: { fallback },
            producer: .lingoScan(appVersion: "0.1.0", build: "1", deviceModel: "iPhone18,2", osVersion: "27.0"),
            now: { clock.now })
        return Harness(service: service, store: store, path: path, fallback: fallback, bookmarks: bookmarks, clock: clock)
    }

    static func seed(_ store: SQLiteStore) async throws {
        let session = SensorSessionRecord(
            sessionID: UUID().uuidString.lowercased(), sensorFamily: .lingo, productType: 9, securityVersion: 3,
            sensorSerialHash: String(repeating: "ab", count: 32), synthetic: false, sensorSerialRedacted: "XYZ…", firmwareHex: "01020304",
            warmupMinutes: 60, wearMinutes: 20_160, activationTimeEpochS: activation, activationTimeSource: .nfcResponse,
            activatedByAppID: "com.otalvaro.lingoscan", activationSource: .thisApp, activationState: .authenticated, receiverIDPresent: true)
        try await store.upsertSession(session)
        let readings = (1...180).map { lc in
            GlucoseReading.make(session: session, lifeCount: lc, raw: RawReading(capped: 100 + lc % 30, uncapped: 102 + lc % 30, trend: 3, qualityFlag: false, channel: 1),
                                origin: .live, receivedAt: UTCInstant(epochSeconds: activation + 60 * Int64(lc) + 2), tzAtCapture: "America/Bogota")
        }
        try await store.insertReadings(readings)
    }

    @Test func exportsToTheICloudContainerFallbackAndReportsIt() async throws {
        let h = try await Self.makeHarness()
        await h.service.refresh()
        #expect(h.service.destination == .appICloudContainer(h.fallback))
        #expect(h.service.destination.isFallback)

        let result = try #require(await h.service.exportNow())
        #expect(result.verified)
        #expect(result.url.deletingLastPathComponent().standardizedFileURL == h.fallback.standardizedFileURL)
        #expect(result.manifest.counts.readings == 180)
        #expect(try await h.store.isArchiveKnown(result.archiveID))
        #expect(h.service.lastError == nil)
        #expect(h.service.packages.count == 1)
        let status = try #require(h.service.packages.first)
        #expect(status.isOwn && status.producerTag == "lingoscan")
        // En un directorio que no es de iCloud el sistema no informa: nunca "respaldado".
        #expect(status.upload == .unknown)
        #expect(!status.upload.isBackedUp)
        #expect(!h.service.isWorking)
    }

    @Test func rememberedFolderWinsOverTheFallbackAndForgettingReturnsToIt() async throws {
        let h = try await Self.makeHarness()
        let chosen = try Self.tempDir("elegida")
        await h.service.chooseFolder(chosen)
        #expect(h.service.destination == .userFolder(chosen.resolvingSymlinksInPath()) || h.service.destination.url?.standardizedFileURL.path == chosen.standardizedFileURL.path
                || h.service.destination.url?.resolvingSymlinksInPath().path == chosen.resolvingSymlinksInPath().path)
        let result = try #require(await h.service.exportNow())
        #expect(result.url.deletingLastPathComponent().resolvingSymlinksInPath().path == chosen.resolvingSymlinksInPath().path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.fallback.path).isEmpty)

        await h.service.forgetFolder()
        #expect(h.service.destination.isFallback)
    }

    @Test func unresolvableBookmarkIsUnavailableNotSilentlyRedirected() async throws {
        let h = try await Self.makeHarness(bookmark: Data("no es un bookmark".utf8))
        await h.service.refresh()
        guard case .unavailable = h.service.destination else { Issue.record("debió quedar no disponible"); return }
        #expect(h.service.packages.isEmpty)
        #expect(await h.service.exportNow() == nil)
        #expect(h.service.lastError?.contains("Elígela de nuevo") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.fallback.path).isEmpty, "no se escribe fuera de la carpeta elegida")
    }

    @Test func dailyExportOnlyRunsWhenDue() async throws {
        let h = try await Self.makeHarness()
        #expect(await h.service.exportIfDue())
        #expect(h.service.packages.count == 1)
        h.clock.advance(3_600)
        #expect(await h.service.exportIfDue())
        #expect(h.service.packages.count == 1, "hay una copia de hace una hora: no se exporta otra")
        h.clock.advance(21 * 3_600)
        #expect(await h.service.exportIfDue())
        #expect(h.service.packages.count == 2)
    }

    @Test func exportThenImportIntoAnotherDatabaseKeepsEverythingAndSkipsRepeats() async throws {
        let a = try await Self.makeHarness()
        let exported = try #require(await a.service.exportNow())
        let b = try await Self.makeHarness(populate: false)
        let first = await b.service.importPackages(from: exported.url)
        guard case .imported(let summary) = try #require(first.first) else { Issue.record("debió importarse"); return }
        #expect(summary.readings.new == 180 && summary.sessions.new == 1)
        #expect(try await b.store.readingCount() == 180)
        // Carpeta entera: el mismo paquete ya es conocido.
        let second = await b.service.importPackages(from: exported.url.deletingLastPathComponent())
        guard case .skipped = try #require(second.first) else { Issue.record("debió omitirse"); return }
        #expect(try await b.store.readingCount() == 180)
        // El propio paquete que la app exportó no se reimporta en su base de origen.
        let own = await a.service.importPackages(from: exported.url)
        guard case .skipped = try #require(own.first) else { Issue.record("el paquete propio debió omitirse"); return }
    }

    @Test func importsTheSharedExampleAndRejectsATamperedCopy() async throws {
        let valid = Self.sharedExamples.appending(path: "LingoScan-lingoscan-20261027T150405Z-3fa85f64.lingoscan", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: valid.path), "faltan los fixtures de LingoScan_Shared")
        let h = try await Self.makeHarness(populate: false)
        let out = await h.service.importPackages(from: valid)
        guard case .imported(let summary) = try #require(out.first) else { Issue.record("debió importarse"); return }
        #expect(summary.readings.new == 163)

        let tampered = try Self.tempDir("copia").appending(path: valid.lastPathComponent, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: valid, to: tampered)
        let readings = tampered.appending(path: "readings.ndjson")
        try Data(String(decoding: try Data(contentsOf: readings), as: UTF8.self).replacingOccurrences(of: "208", with: "209").utf8).write(to: readings)
        let h2 = try await Self.makeHarness(populate: false)
        let rejected = await h2.service.importPackages(from: tampered)
        guard case .rejected(_, _, let code) = try #require(rejected.first) else { Issue.record("debió rechazarse"); return }
        #expect(code == "hash_mismatch")
        #expect(try await h2.store.readingCount() == 0)
        #expect(h2.service.lastError != nil)
    }

    @Test func abandonedPartialsAreRemovedOnlyForThisProducer() async throws {
        let h = try await Self.makeHarness()
        let fm = FileManager.default
        try fm.createDirectory(at: h.fallback.appending(path: "LingoScan-lingoscan-20261027T160500Z-eeeeeeee.lingoscan.partial"), withIntermediateDirectories: false)
        try fm.createDirectory(at: h.fallback.appending(path: "LingoScan-astra-20261027T160500Z-ffffffff.lingoscan.partial"), withIntermediateDirectories: false)
        await h.service.removeAbandonedPartials()
        #expect(try fm.contentsOfDirectory(atPath: h.fallback.path) == ["LingoScan-astra-20261027T160500Z-ffffffff.lingoscan.partial"])
    }

    @Test func producerInfoDescribesThisInstall() {
        let p = ArchiveService.currentProducer()
        #expect(p.appID == "com.otalvaro.lingoscan" && p.producerTag == "lingoscan")
        #expect(!p.deviceModel.isEmpty && p.osVersion.split(separator: ".").count == 3)
    }

    @Test func backgroundTaskIdentifierIsPermittedInInfoPlist() {
        #expect(ArchiveBackgroundTask.refreshIdentifier == "com.otalvaro.lingoscan.archive.refresh")
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(permitted?.contains(ArchiveBackgroundTask.refreshIdentifier) == true)
    }
}
