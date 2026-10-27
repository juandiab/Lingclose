import Foundation
import Testing
@testable import LingoScan

struct ArchiveDestinationSummaryTests {
    @Test func chosenFolderNamesTheFolder() {
        let summary = ArchiveDestinationSummary(.userFolder(URL(filePath: "/tmp/Respaldo")))
        #expect(summary == .chosenFolder(name: "Respaldo"))
        #expect(summary.title.contains("Respaldo"))
    }

    @Test func appContainerSaysICloudAndLingoScan() {
        let summary = ArchiveDestinationSummary(.appICloudContainer(URL(filePath: "/tmp/icloud")))
        #expect(summary == .appICloudContainer)
        #expect(summary.title.contains("iCloud"))
        #expect(summary.title.contains("LingoScan"))
    }

    @Test func unavailableIsNoDestination() {
        let summary = ArchiveDestinationSummary(.unavailable("motivo"))
        #expect(summary == .none)
        #expect(!summary.title.isEmpty)
        #expect(summary.title != ArchiveDestinationSummary.appICloudContainer.title)
    }

    @Test func recoveryFolderKindsMapToTheSameSummaries() {
        #expect(ArchiveDestinationSummary(kind: .chosen, folderName: "X") == .chosenFolder(name: "X"))
        #expect(ArchiveDestinationSummary(kind: .appICloudContainer, folderName: "Documents") == .appICloudContainer)
        #expect(ArchiveDestinationSummary(kind: .documents, folderName: "Documents") == .appDocuments)
    }
}
