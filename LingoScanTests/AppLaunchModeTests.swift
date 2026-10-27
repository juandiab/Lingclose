import Foundation
import Testing
@testable import LingoScan

struct AppLaunchModeTests {
    private func defaults() throws -> UserDefaults {
        let name = "t08b-launch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func withoutPreviewArgumentTheAppIsLive() throws {
        let mode = AppLaunchMode.resolve(defaults: try defaults())
        #expect(mode == .live)
        #expect(!mode.usesPreviewData)
    }

    @Test func testHostLaunchIsLive() {
        // El host de tests se lanza sin `-previewSensorState`.
        #expect(!ProcessInfo.processInfo.arguments.contains("-previewSensorState"))
        #expect(AppLaunchMode.resolve() == .live)
        #expect(PreviewData.launchSensorState == nil)
    }

    @Test func previewArgumentSelectsPreviewData() throws {
        let defaults = try defaults()
        defaults.set("readyToActivate", forKey: AppLaunchMode.previewArgumentKey)
        #if DEBUG
        #expect(AppLaunchMode.resolve(defaults: defaults) == .preview(.readyToActivate))
        #else
        #expect(AppLaunchMode.resolve(defaults: defaults) == .live)
        #endif
    }
}
