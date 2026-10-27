import Foundation
import LingoCore

/// Umbrales y activación de alarmas en `UserDefaults` del App Group, para que un widget o la
/// extensión del Watch puedan leerlos más adelante. Los valores se acotan al leer y al escribir.
struct AlarmSettingsStore: Sendable {
    static let appGroupID = "group.com.otalvaro.lingoscan"
    static let key = "lingoscan.alarm.settings.v1"

    /// `UserDefaults` es seguro entre hilos (documentado por Apple), aunque no esté marcado `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// App Group si está disponible; si no, `standard` (no debería ocurrir con el entitlement).
    static func appGroup() -> AlarmSettingsStore {
        AlarmSettingsStore(defaults: UserDefaults(suiteName: appGroupID) ?? .standard)
    }

    func load() -> AlarmSettings {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(AlarmSettings.self, from: data)
        else { return .default }
        return decoded.normalized()
    }

    func save(_ settings: AlarmSettings) {
        guard let data = try? JSONEncoder().encode(settings.normalized()) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
