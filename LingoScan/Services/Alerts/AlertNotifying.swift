import Foundation

/// Costura sobre `UNUserNotificationCenter`; los tests inyectan un doble.
protocol AlertNotifying: Sendable {
    func authorization() async -> AlertPermission
    /// Pide `.alert, .sound, .badge`. Si ya se decidió, iOS no vuelve a preguntar.
    func requestAuthorization() async -> Bool
    /// Muestra la notificación ya.
    func deliver(_ notification: AlertNotification) async throws
    /// Programa la notificación para `date` (la entrega iOS aunque la app esté suspendida).
    func schedule(_ notification: AlertNotification, at date: Date) async throws
    func cancelPending(ids: [String]) async
}
