import Foundation
import Testing
@testable import LingoScan

struct RecoveryShareFileTests {
    private struct NoBookmarks: FolderBookmarkStoring {
        func load() -> Data? { nil }
        func save(_ data: Data?) {}
    }

    private func record(_ url: URL) -> RecoveryService.ExportRecord {
        RecoveryService.ExportRecord(fileName: url.lastPathComponent, fileURL: url, at: Date(), trigger: "manual", sessions: [])
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "share-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func noRecordMeansNone() {
        #expect(RecoveryShareFile.prepare(record: nil, folderKind: .fixed, bookmarks: NoBookmarks()) == .none)
    }

    @Test func missingFileIsReported() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = RecoveryShareFile.prepare(
            record: record(dir.appending(path: "gone.json")), folderKind: .fixed, bookmarks: NoBookmarks(), temporaryDirectory: dir)
        #expect(result == .missing)
    }

    @Test func existingFileIsCopiedToATemporary() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "copia.json")
        try Data("x".utf8).write(to: source)
        let result = RecoveryShareFile.prepare(
            record: record(source), folderKind: .fixed, bookmarks: NoBookmarks(), temporaryDirectory: dir)
        guard case .ready(let url) = result else { Issue.record("esperaba .ready"); return }
        #expect(url != source)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
