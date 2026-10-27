import Foundation
import Testing
import LingoCore
@testable import LingoScan

@MainActor
struct ExportCooldownTests {
    private func makeModel(cooldown: Duration, archive: FakeArchive) -> DataViewModel {
        DataViewModel(archive: archive, health: FakeHealth(HealthSnapshot()), eventLog: FakeEventLog(entries: []), exportCooldown: cooldown)
    }

    private func summary() -> ArchiveExportSummary {
        ArchiveExportSummary(packageName: "P.lingoscan", readings: 5, events: 1, verified: true, failure: nil)
    }

    @Test func defaultCooldownIsTenSecondsAndRetentionIsSeven() {
        #expect(DataViewModel.defaultExportCooldown == .seconds(10))
        #expect(DataViewModel.retainedPackages == 7)
    }

    @Test func exportBlocksFurtherTapsUntilTheCooldownEnds() async throws {
        let archive = FakeArchive()
        archive.exportResult = summary()
        let model = makeModel(cooldown: .milliseconds(150), archive: archive)
        #expect(model.canExport)
        await model.exportNow()
        #expect(model.isExportCoolingDown)
        #expect(!model.canExport)
        await model.exportNow()
        await model.exportNow()
        #expect(archive.exportCount == 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!model.isExportCoolingDown)
        #expect(model.canExport)
        await model.exportNow()
        #expect(archive.exportCount == 2)
    }

    @Test func failedExportDoesNotLock() async {
        let archive = FakeArchive()
        archive.exportResult = nil
        let model = makeModel(cooldown: .seconds(10), archive: archive)
        await model.exportNow()
        #expect(!model.isExportCoolingDown)
        #expect(model.canExport)
    }

    @Test func useAppFolderIsOnlyEnabledWhenAFolderWasChosen() async {
        let archive = FakeArchive()
        let model = makeModel(cooldown: .seconds(10), archive: archive)
        #expect(!model.canUseAppFolder)
        await model.chooseFolder(URL(filePath: "/tmp/Respaldo"))
        #expect(model.canUseAppFolder)
    }
}
