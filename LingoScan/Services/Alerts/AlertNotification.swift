import LingoCore

/// Notificación local ya compuesta, independiente de `UserNotifications` para poder probarla.
struct AlertNotification: Sendable, Equatable {
    static let categoryIdentifier = "lingoscan.alert"

    let id: String
    /// `nil` en la notificación de prueba de Ajustes.
    let kind: AlertKind?
    let title: String
    let body: String
    /// `.timeSensitive` para baja y bajada rápida (atraviesan un modo de concentración); `.active` para el resto.
    let isTimeSensitive: Bool

    /// Hilo por tipo (`lingoscan.alert.high`, …): iOS agrupa los avisos del mismo tipo.
    var threadIdentifier: String { "lingoscan.alert.\(kind?.rawValue ?? "test")" }
}
