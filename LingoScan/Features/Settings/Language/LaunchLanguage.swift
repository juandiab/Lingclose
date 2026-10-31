import Foundation

/// Idioma con el que arrancó el proceso. iOS lee `AppleLanguages` al arrancar, así que mientras el proceso viva la
/// interfaz sigue en este idioma aunque se elija otro en Ajustes. Se guarda una sola vez por proceso
/// (`LaunchLanguage.process`) para que el aviso "Pendiente de reabrir la app" no desaparezca si la fila de Idioma se
/// recrea (duda abierta de T-29).
struct LaunchLanguage: Equatable, Sendable {
    let preference: LanguagePreference

    init(defaults: UserDefaults) {
        preference = LanguagePreference.current(defaults: defaults)
    }

    /// Se lee la primera vez que se usa, al construir Ajustes: siempre antes de que el usuario cambie el idioma,
    /// porque solo se cambia desde ahí.
    static let process = LaunchLanguage(defaults: .standard)

    /// La elección difiere del idioma con el que corre la app: hace falta reabrirla.
    func needsRelaunch(for selection: LanguagePreference) -> Bool {
        selection != preference
    }
}
