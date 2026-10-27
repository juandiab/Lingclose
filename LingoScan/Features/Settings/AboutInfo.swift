import Foundation

/// Versión y procedencia mostradas en "Acerca de".
struct AboutInfo: Equatable, Sendable {
    let version: String
    let build: String
    /// Commit base de `RoundWhiteDiscKit` (fork); ver `docs/FORK_RWDK.md`.
    let forkBaseCommit: String

    static let forkBaseCommit = "7dd6396"

    init(version: String, build: String, forkBaseCommit: String = AboutInfo.forkBaseCommit) {
        self.version = version
        self.build = build
        self.forkBaseCommit = forkBaseCommit
    }

    init(bundle: Bundle = .main) {
        self.init(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
    }
}
