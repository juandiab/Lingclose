import Foundation
import Testing
import LingoCore
import os
@testable import LingoScan

@MainActor
final class FakeArchive: ArchiveManaging {
    var destination: ArchiveDestination = .appICloudContainer(URL(filePath: "/tmp/icloud"))
    var packages: [ArchivePackageStatus] = []
    var isWorking = false
    var lastError: String?
    var exportResult: ArchiveExportSummary?
    var importResult: [ArchiveImportLine] = []
    private(set) var chosenFolders: [URL] = []
    private(set) var importedURLs: [URL] = []
    private(set) var refreshCount = 0
    private(set) var exportCount = 0

    func refresh() async { refreshCount += 1 }

    func chooseFolder(_ url: URL) async {
        chosenFolders.append(url)
        destination = .userFolder(url)
    }

    func forgetFolder() async { destination = .appICloudContainer(URL(filePath: "/tmp/icloud")) }

    func exportNow() async -> ArchiveExportSummary? {
        exportCount += 1
        return exportResult
    }

    func importPackages(from url: URL) async -> [ArchiveImportLine] {
        importedURLs.append(url)
        return importResult
    }
}

final class FakeHealth: HealthControlling {
    private let state = OSAllocatedUnfairLock(initialState: (snapshot: HealthSnapshot(), fillCalls: 0, authCalls: 0))
    let fillSummary = HealthDrainSummary(written: 3)

    init(_ snapshot: HealthSnapshot) {
        state.withLock { $0.snapshot = snapshot }
    }

    var fillCalls: Int { state.withLock { $0.fillCalls } }
    var authCalls: Int { state.withLock { $0.authCalls } }

    func snapshot() async -> HealthSnapshot { state.withLock { $0.snapshot } }

    func requestAuthorization() async -> HealthSnapshot {
        state.withLock {
            $0.authCalls += 1
            $0.snapshot.isAuthorized = true
            return $0.snapshot
        }
    }

    func fillGaps() async -> HealthFillResult {
        let summary = fillSummary
        return state.withLock {
            $0.fillCalls += 1
            $0.snapshot.pendingCount = 0
            $0.snapshot.lastAttempt = Date(timeIntervalSince1970: 1_800_000_000)
            return HealthFillResult(summary: summary, snapshot: $0.snapshot)
        }
    }
}

struct FakeEventLog: EventLogReading {
    let entries: [EventLogEntry]

    func recentLogEvents(limit: Int) async throws -> [EventLogEntry] { Array(entries.prefix(limit)) }
}

@MainActor
struct DataViewModelTests {
    private func entry(_ id: Int64, _ level: EventLogLevel, _ category: String = "health") -> EventLogEntry {
        EventLogEntry(id: id, at: UTCInstant(epochSeconds: 1_800_000_000 + id), level: level, category: category, message: "m\(id)")
    }

    private func makeModel(
        health: HealthSnapshot = HealthSnapshot(), archive: FakeArchive = FakeArchive(), entries: [EventLogEntry] = []
    ) -> (DataViewModel, FakeArchive, FakeHealth) {
        let fake = FakeHealth(health)
        return (DataViewModel(archive: archive, health: fake, eventLog: FakeEventLog(entries: entries)), archive, fake)
    }

    // MARK: Health

    @Test func healthStatusFollowsAuthorizationPauseAndPending() async {
        let (model, _, _) = makeModel(health: HealthSnapshot(isAuthorized: false, pendingCount: 5))
        await model.refresh()
        #expect(model.healthStatus == .notAuthorized)
        #expect(!model.canFillGaps)

        let (pending, _, _) = makeModel(health: HealthSnapshot(isAuthorized: true, pendingCount: 12))
        await pending.refresh()
        #expect(pending.healthStatus == .pending(12))
        #expect(pending.canFillGaps)

        let (clean, _, _) = makeModel(health: HealthSnapshot(isAuthorized: true, pendingCount: 0))
        await clean.refresh()
        #expect(clean.healthStatus == .upToDate)
        #expect(!clean.canFillGaps)

        let (paused, _, _) = makeModel(health: HealthSnapshot(isAuthorized: true, pendingCount: 4, isPaused: true))
        await paused.refresh()
        #expect(paused.healthStatus == .paused)
        #expect(!paused.canFillGaps)
    }

    @Test func requestingAuthorizationUpdatesTheSnapshot() async {
        let (model, _, health) = makeModel(health: HealthSnapshot(isAuthorized: false, pendingCount: 2))
        await model.refresh()
        await model.requestHealthAuthorization()
        #expect(model.health.isAuthorized)
        #expect(model.healthStatus == .pending(2))
        #expect(health.authCalls == 1)
    }

    @Test func fillGapsOnlyRunsWhenAllowedAndRecordsTheAttempt() async {
        let (blocked, _, blockedHealth) = makeModel(health: HealthSnapshot(isAuthorized: false, pendingCount: 9))
        await blocked.refresh()
        await blocked.fillGaps()
        #expect(blockedHealth.fillCalls == 0)
        #expect(blocked.lastFill == nil)

        let (model, _, health) = makeModel(health: HealthSnapshot(isAuthorized: true, pendingCount: 9))
        await model.refresh()
        #expect(model.health.lastAttempt == nil)
        await model.fillGaps()
        #expect(health.fillCalls == 1)
        #expect(model.lastFill?.written == 3)
        #expect(model.health.pendingCount == 0)
        #expect(model.health.lastAttempt != nil)
        #expect(model.healthStatus == .upToDate)
    }

    // MARK: Archivo

    @Test func exportNowStoresTheSummaryAndShowsDestinationState() async {
        let archive = FakeArchive()
        archive.exportResult = ArchiveExportSummary(packageName: "LingoScan-lingoscan-X.lingoscan", readings: 120, events: 3, verified: true, failure: nil)
        let (model, _, _) = makeModel(archive: archive)
        #expect(model.destination.isFallback)
        await model.exportNow()
        #expect(archive.exportCount == 1)
        #expect(model.exportSummary?.verified == true)
        #expect(model.exportSummary?.readings == 120)
    }

    @Test func choosingAFolderChangesTheDestination() async {
        let (model, archive, _) = makeModel()
        let folder = URL(filePath: "/tmp/Respaldo")
        await model.chooseFolder(folder)
        #expect(archive.chosenFolders == [folder])
        #expect(model.destination == .userFolder(folder))
        #expect(!model.destination.isFallback)
        await model.forgetFolder()
        #expect(model.destination.isFallback)
    }

    @Test func unavailableDestinationBlocksNothingButHasNoURL() async {
        let archive = FakeArchive()
        archive.destination = .unavailable("La carpeta elegida ya no es accesible. Elígela de nuevo.")
        let (model, _, _) = makeModel(archive: archive)
        #expect(model.destination.url == nil)
    }

    @Test func importKeepsOneLinePerPackageAndRefreshes() async {
        let archive = FakeArchive()
        archive.importResult = [
            ArchiveImportLine(id: 0, outcome: .imported(producer: "com.example.astra", new: 10, updated: 1, identical: 2, conflicts: 0)),
            ArchiveImportLine(id: 1, outcome: .skipped(producer: "com.otalvaro.lingoscan")),
            ArchiveImportLine(id: 2, outcome: .rejected(name: "bad.lingoscan", reason: "hash distinto")),
        ]
        let (model, _, _) = makeModel(archive: archive)
        let url = URL(filePath: "/tmp/paquetes")
        await model.importPackages(from: url)
        #expect(archive.importedURLs == [url])
        #expect(model.importLines.count == 3)
        #expect(archive.refreshCount == 1)
        if case .rejected(let name, _) = model.importLines[2].outcome { #expect(name == "bad.lingoscan") } else { Issue.record("se esperaba un rechazo") }
    }

    @Test func visiblePackagesAreTheMostRecentFive() async {
        let archive = FakeArchive()
        archive.packages = (0..<8).map { index in
            ArchivePackageStatus(
                name: "p\(index)", url: URL(filePath: "/tmp/p\(index)"), producerTag: "lingoscan",
                createdAt: UTCInstant(epochSeconds: Int64(1_800_000_000 - index * 100)), isOwn: true, upload: .icloudUploaded)
        }
        let (model, _, _) = makeModel(archive: archive)
        #expect(model.visiblePackageList.map(\.name) == ["p0", "p1", "p2", "p3", "p4"])
    }

    @Test func uploadStateTextNeverClaimsBackupWithoutProof() {
        #expect(ArchiveUploadState.localWritten.title != ArchiveUploadState.icloudUploaded.title)
        #expect(!ArchiveUploadState.localWritten.isBackedUp)
        #expect(ArchiveUploadState.unknown.title != ArchiveUploadState.icloudUploaded.title)
        #expect(ArchiveUploadState.icloudUploaded.isBackedUp)
        #expect(!ArchiveUploadState.unknown.isBackedUp)
    }

    // MARK: Errores recientes

    @Test func recentErrorsKeepOnlyWarningsAndErrors() async {
        let entries = [entry(5, .info), entry(4, .error, "archive"), entry(3, .debug), entry(2, .warning), entry(1, .info)]
        let (model, _, _) = makeModel(entries: entries)
        await model.refresh()
        #expect(model.recentErrors.map(\.id) == [4, 2])
    }

    @Test func recentErrorsAreCapped() async {
        let entries = (1...20).map { entry(Int64($0), .error) }
        let (model, _, _) = makeModel(entries: entries)
        await model.refresh()
        #expect(model.recentErrors.count == DataViewModel.visibleErrors)
    }
}
