import Foundation
import LingoCore
import Testing
@testable import LingoScan

struct FolderBookmarkTests {
    @Test func bookmarkRoundTripsAFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "t10-bm-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try SecurityScopedAccess.run(dir) { try FolderBookmark.make(from: dir) }
        let resolved = try FolderBookmark.resolve(data)
        #expect(resolved.url.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path)
        #expect(!resolved.isStale && resolved.refreshedData == nil)
    }

    @Test func rejectsFilesAndGarbage() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "t10-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        #expect(throws: FolderBookmark.Failure.notAFolder) { try FolderBookmark.make(from: file) }
        #expect(throws: FolderBookmark.Failure.self) { try FolderBookmark.resolve(Data("basura".utf8)) }
    }

    @Test func userDefaultsStorePersistsAndClears() {
        let suite = "t10-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsFolderBookmarkStore(defaults: defaults, key: "k")
        #expect(store.load() == nil)
        store.save(Data([1, 2, 3]))
        #expect(store.load() == Data([1, 2, 3]))
        store.save(nil)
        #expect(store.load() == nil)
    }

    @Test func securityScopedAccessRunsTheBodyForUnscopedURLs() {
        let url = FileManager.default.temporaryDirectory
        let value = SecurityScopedAccess.run(url) { 42 }
        #expect(value == 42)
    }
}

struct ICloudItemStatusTests {
    @Test func localPackageReportsUnknownAndNeverBackedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "t10-icloud-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: dir.appending(path: "manifest.json"))
        try Data("b".utf8).write(to: dir.appending(path: "sessions.json"))
        let state = ICloudItemStatus.state(ofPackage: dir)
        #expect(state == .unknown && !state.isBackedUp)
        #expect(ICloudItemStatus.state(ofItem: dir.appending(path: "no-existe")) == .unknown)
    }

    @Test func downloadCheckIsImmediateForNonUbiquitousItems() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "t10-dl-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: dir.appending(path: "manifest.json"))
        #expect(await ICloudItemStatus.ensureDownloaded(package: dir, timeout: .milliseconds(100)))
    }
}
