import Foundation
import Testing
@testable import LingoScan

/// T-31: el idioma de arranque se fija una vez; cambiar la preferencia después no lo mueve, así que el aviso
/// "Pendiente de reabrir la app" sigue visible aunque la fila de Idioma se recree.
struct LaunchLanguageTests {
    private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "LaunchLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test func capturesThePreferenceAtLaunch() throws {
        try withTemporaryDefaults { defaults in
            LanguagePreference.english.apply(defaults: defaults)
            #expect(LaunchLanguage(defaults: defaults).preference == .english)
        }
    }

    @Test func laterChangesKeepTheRelaunchNotice() throws {
        try withTemporaryDefaults { defaults in
            let launch = LaunchLanguage(defaults: defaults)
            #expect(launch.preference == .system)
            #expect(!launch.needsRelaunch(for: .system))

            LanguagePreference.portugueseBrazil.apply(defaults: defaults)
            // Una fila nueva lee la selección guardada, pero compara con el mismo idioma de arranque.
            let selection = LanguagePreference.current(defaults: defaults)
            #expect(selection == .portugueseBrazil)
            #expect(launch.preference == .system)
            #expect(launch.needsRelaunch(for: selection))
        }
    }

    @Test func goingBackToTheLaunchLanguageClearsTheNotice() throws {
        try withTemporaryDefaults { defaults in
            LanguagePreference.spanish.apply(defaults: defaults)
            let launch = LaunchLanguage(defaults: defaults)
            #expect(launch.needsRelaunch(for: .english))
            #expect(!launch.needsRelaunch(for: .spanish))
        }
    }

    @Test func processSnapshotIsStable() {
        #expect(LaunchLanguage.process == LaunchLanguage.process)
    }
}
