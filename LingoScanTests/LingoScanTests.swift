import Testing
import LingoCore

struct LingoScanTests {
    @Test func lingoCoreVersionIsExposed() {
        #expect(LingoCore.version == "0.1.0")
    }
}
