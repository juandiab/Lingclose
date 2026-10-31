import Foundation
import Testing
@testable import LingoScan

/// T-29: el idioma de la app se guarda como `AppleLanguages` del dominio de la app más una marca propia.
/// Cada test usa un `UserDefaults(suiteName:)` temporal que se borra al terminar.
struct LanguagePreferenceTests {
    private let appleLanguages = LanguagePreference.appleLanguagesKey
    private let marker = LanguagePreference.overrideKey

    /// Ejecuta `body` con un dominio temporal y lo elimina al salir.
    private func withTemporaryDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suiteName = "LanguagePreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }

    /// Valor guardado en el propio dominio (sin el global que `UserDefaults` consulta de respaldo).
    private func stored(_ key: String, in defaults: UserDefaults, suite: String) -> Any? {
        defaults.persistentDomain(forName: suite)?[key]
    }

    @Test func systemByDefault() throws {
        try withTemporaryDefaults { defaults, _ in
            #expect(LanguagePreference.current(defaults: defaults) == .system)
        }
    }

    @Test(arguments: [
        (LanguagePreference.spanish, "es"),
        (LanguagePreference.english, "en"),
        (LanguagePreference.portugueseBrazil, "pt-BR"),
    ])
    func languageWritesCodeAndMarker(preference: LanguagePreference, code: String) throws {
        try withTemporaryDefaults { defaults, suite in
            preference.apply(defaults: defaults)
            #expect(stored(appleLanguages, in: defaults, suite: suite) as? [String] == [code])
            #expect(stored(marker, in: defaults, suite: suite) as? String == code)
        }
    }

    @Test func systemRemovesCodeAndMarker() throws {
        try withTemporaryDefaults { defaults, suite in
            LanguagePreference.english.apply(defaults: defaults)
            LanguagePreference.system.apply(defaults: defaults)
            #expect(stored(appleLanguages, in: defaults, suite: suite) == nil)
            #expect(stored(marker, in: defaults, suite: suite) == nil)
            #expect(LanguagePreference.current(defaults: defaults) == .system)
        }
    }

    /// `AppleLanguages` puesto por iOS (sin la marca propia) no cuenta como elección de la app.
    @Test func appleLanguagesWithoutMarkerIsSystem() throws {
        try withTemporaryDefaults { defaults, _ in
            defaults.set(["es"], forKey: appleLanguages)
            #expect(LanguagePreference.current(defaults: defaults) == .system)
            defaults.set(["es-CO", "en"], forKey: appleLanguages)
            #expect(LanguagePreference.current(defaults: defaults) == .system)
        }
    }

    @Test(arguments: LanguagePreference.allCases)
    func roundTrip(preference: LanguagePreference) throws {
        try withTemporaryDefaults { defaults, _ in
            preference.apply(defaults: defaults)
            #expect(LanguagePreference.current(defaults: defaults) == preference)
        }
    }

    @Test func displayNamesAreEndonyms() {
        #expect(LanguagePreference.spanish.displayName == "Español")
        #expect(LanguagePreference.english.displayName == "English")
        #expect(LanguagePreference.portugueseBrazil.displayName == "Português (Brasil)")
    }
}
