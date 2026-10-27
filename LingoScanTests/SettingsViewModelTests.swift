import Foundation
import Testing
@testable import LingoScan

@MainActor
struct SettingsViewModelTests {
    struct FakePermissions: PermissionsProviding {
        var bluetooth: PermissionState = .notDetermined
        var nfcAvailable = false
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsViewModelTests-\(UUID().uuidString)") ?? .standard
    }

    @Test func diagnosticsPreferencePersists() {
        let defaults = makeDefaults()
        let first = SettingsViewModel(permissions: FakePermissions(), health: nil, defaults: defaults)
        #expect(!first.privateDiagnostics)
        first.privateDiagnostics = true
        let second = SettingsViewModel(permissions: FakePermissions(), health: nil, defaults: defaults)
        #expect(second.privateDiagnostics)
    }

    @Test func permissionsAreReadWithoutAskingForThem() async {
        let health = PreviewHealthController(current: HealthSnapshot(isAuthorized: true))
        let model = SettingsViewModel(
            permissions: FakePermissions(bluetooth: .granted, nfcAvailable: true), health: health, defaults: makeDefaults())
        #expect(model.bluetooth == .granted)
        #expect(model.nfcAvailable)
        #expect(!model.healthAuthorized)
        await model.refreshPermissions()
        #expect(model.healthAuthorized)
    }

    @Test func unitIsFixedAndAboutShowsVersionBuildAndForkBase() {
        let model = SettingsViewModel(
            permissions: FakePermissions(), health: nil, about: AboutInfo(version: "0.1.0", build: "7"), defaults: makeDefaults())
        #expect(model.glucoseUnit == "mg/dL")
        #expect(model.about.version == "0.1.0")
        #expect(model.about.build == "7")
        #expect(model.about.forkBaseCommit == "7dd6396")
    }

    @Test func aboutReadsTheBundle() {
        let about = AboutInfo(bundle: .main)
        #expect(about.version != "?")
        #expect(about.build != "?")
    }
}

struct AppearanceModeTests {
    @Test func storedValuesMapToColorSchemes() {
        #expect(AppearanceMode(stored: "system").colorScheme == nil)
        #expect(AppearanceMode(stored: "light").colorScheme == .light)
        #expect(AppearanceMode(stored: "dark").colorScheme == .dark)
    }

    @Test func unknownOrMissingValueFallsBackToSystem() {
        #expect(AppearanceMode(stored: nil) == .system)
        #expect(AppearanceMode(stored: "sepia") == .system)
        #expect(AppearanceMode.allCases.map(\.rawValue) == ["system", "light", "dark"])
    }

    @Test func referenceRangesCanNeverCross() {
        #expect(ReferenceLines.lowRange.upperBound < ReferenceLines.highRange.lowerBound)
        let clamped = ReferenceLines.clampedForSettings(low: 300, high: 10)
        #expect(clamped.low == 100)
        #expect(clamped.high == 120)
        #expect(clamped.low < clamped.high)
        #expect(ReferenceLines.clampedForSettings(low: 70, high: 140) == (70, 140))
    }

    @Test @MainActor func statsFollowTheReferenceLines() async {
        let data = PreviewData()
        let model = TodayViewModel(dataSource: data, sensorSource: data)
        await model.refresh()
        #expect(model.stats.range == 70...140)
        model.referenceLow = 80
        model.referenceHigh = 160
        #expect(model.stats.range == 80...160)
    }
}
