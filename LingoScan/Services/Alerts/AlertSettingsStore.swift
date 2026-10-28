import Foundation
import LingoCore

/// Ajustes y estado de las alertas como JSON en `UserDefaults` del App Group (un widget podría leerlos).
/// Sin migración de SQLite. La primera vez hereda los interruptores de las alarmas anteriores (`lingoscan.alarm.settings.v1`).
struct AlertSettingsStore: Sendable {
    static let appGroupID = "group.com.otalvaro.lingoscan"
    static let settingsKey = "lingoscan.alerts.settings.v1"
    static let stateKey = "lingoscan.alerts.state.v1"
    static let pendingNoDataKey = "lingoscan.alerts.pendingNoData.v1"
    static let legacyAlarmKey = "lingoscan.alarm.settings.v1"

    /// `UserDefaults` es seguro entre hilos (documentado por Apple), aunque no esté marcado `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func appGroup() -> AlertSettingsStore {
        AlertSettingsStore(defaults: UserDefaults(suiteName: appGroupID) ?? .standard)
    }

    func loadSettings() -> AlertSettings {
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AlertSettings.self, from: data) {
            return decoded.normalized()
        }
        return legacySettings() ?? .default
    }

    func saveSettings(_ settings: AlertSettings) {
        guard let data = try? JSONEncoder().encode(settings.normalized()) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    func loadState() -> AlertState {
        defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(AlertState.self, from: $0) } ?? AlertState()
    }

    func saveState(_ state: AlertState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }

    /// Hora de la notificación "sin datos" programada, si la hay.
    var pendingNoDataAt: UTCInstant? {
        get { (defaults.object(forKey: Self.pendingNoDataKey) as? NSNumber).map { UTCInstant(epochSeconds: $0.int64Value) } }
        nonmutating set {
            if let newValue { defaults.set(NSNumber(value: newValue.epochSeconds), forKey: Self.pendingNoDataKey) }
            else { defaults.removeObject(forKey: Self.pendingNoDataKey) }
        }
    }

    /// Alarmas anteriores a T-24: si el usuario las configuró, se conservan sus interruptores y el plazo "sin datos".
    private func legacySettings() -> AlertSettings? {
        struct Legacy: Decodable {
            let lowEnabled: Bool
            let highEnabled: Bool
            let noDataEnabled: Bool
            let noDataMinutes: Int
        }
        guard let data = defaults.data(forKey: Self.legacyAlarmKey),
              let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else { return nil }
        var settings = AlertSettings(isEnabled: true, noDataAfterMinutes: legacy.noDataMinutes)
        settings.setEnabled(legacy.lowEnabled, for: .low)
        settings.setEnabled(legacy.highEnabled, for: .high)
        settings.setEnabled(legacy.noDataEnabled, for: .noData)
        return settings.normalized()
    }
}
