import Foundation

/// Guarda la última `CoachingRecord` como JSON en `UserDefaults` del App Group (lo escribe el servicio de alertas,
/// también en segundo plano, y lo leen el delegado de notificaciones y Hoy).
struct CoachingStore: Sendable {
    static let key = "lingoscan.coaching.latest.v1"

    /// `UserDefaults` es seguro entre hilos (documentado por Apple), aunque no esté marcado `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func appGroup() -> CoachingStore {
        CoachingStore(defaults: UserDefaults(suiteName: AlertSettingsStore.appGroupID) ?? .standard)
    }

    func latest() -> CoachingRecord? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(CoachingRecord.self, from: $0) }
    }

    /// Una alerta nueva reemplaza a la anterior (y su estado de cerrada).
    func save(_ record: CoachingRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Se tocó la notificación `id`: la tarjeta se mostrará en Hoy.
    func markOpened(id: String, at date: Date) {
        guard var record = latest(), record.id == id else { return }
        record.openedAt = date
        save(record)
    }

    func dismiss(id: String) {
        guard var record = latest(), record.id == id else { return }
        record.isDismissed = true
        save(record)
    }
}
