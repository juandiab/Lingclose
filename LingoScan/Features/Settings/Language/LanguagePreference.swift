import Foundation

/// Idioma de la app elegido en Ajustes. Se guarda como `AppleLanguages` en el dominio de la app, que iOS lee al
/// arrancar el proceso: el cambio se aplica al volver a abrir la app. La marca `app.language.override` distingue
/// una elección propia de un `AppleLanguages` que puso iOS (dominio global o idioma por app de Ajustes de iOS).
enum LanguagePreference: String, Sendable, CaseIterable, Identifiable {
    case system
    case spanish = "es"
    case english = "en"
    case portugueseBrazil = "pt-BR"

    static let appleLanguagesKey = "AppleLanguages"
    static let overrideKey = "app.language.override"

    var id: Self { self }

    /// Código de idioma para `AppleLanguages`; `nil` en `.system`.
    var languageCode: String? {
        self == .system ? nil : rawValue
    }

    /// Nombre visible: "Sistema" localizado; los idiomas, en su propio idioma (endónimo).
    var displayName: String {
        switch self {
        case .system: String(localized: "settings.language.system", defaultValue: "Sistema")
        case .spanish: "Español"
        case .english: "English"
        case .portugueseBrazil: "Português (Brasil)"
        }
    }

    /// Preferencia vigente: un idioma solo si `AppleLanguages` empieza por su código y existe la marca propia.
    static func current(defaults: UserDefaults) -> LanguagePreference {
        guard defaults.string(forKey: overrideKey) != nil,
              let first = defaults.stringArray(forKey: appleLanguagesKey)?.first,
              let preference = LanguagePreference(rawValue: first),
              preference != .system else {
            return .system
        }
        return preference
    }

    /// Escribe la preferencia. `.system` borra `AppleLanguages` del dominio de la app y la marca.
    func apply(defaults: UserDefaults) {
        if let languageCode {
            defaults.set([languageCode], forKey: Self.appleLanguagesKey)
            defaults.set(languageCode, forKey: Self.overrideKey)
        } else {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
            defaults.removeObject(forKey: Self.overrideKey)
        }
    }
}
