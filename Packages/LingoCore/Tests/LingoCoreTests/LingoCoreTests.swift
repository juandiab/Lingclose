import Testing
@testable import LingoCore

struct LingoCoreTests {
    @Test func versionIsSet() {
        #expect(LingoCore.version == "0.1.0")
    }
}
