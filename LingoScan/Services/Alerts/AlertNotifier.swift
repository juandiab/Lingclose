import Foundation
import UserNotifications

/// `AlertNotifying` real sobre `UNUserNotificationCenter`. Sin critical alerts (exigen un permiso especial de Apple):
/// la baja y la bajada rápida van como `.timeSensitive` (entitlement `usernotifications.time-sensitive`).
struct AlertNotifier: AlertNotifying {
    static let openTodayActionID = "lingoscan.alert.openToday"
    static let coachingUserInfoKey = "coachingID"

    func authorization() async -> AlertPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func deliver(_ notification: AlertNotification) async throws {
        try await add(notification, trigger: nil)
    }

    func schedule(_ notification: AlertNotification, at date: Date) async throws {
        let interval = max(1, date.timeIntervalSinceNow)
        try await add(notification, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    func cancelPending(ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Categoría con la acción "Ver Hoy" (abre la app; sin acciones destructivas). Llamar al arrancar.
    static func registerCategories() {
        let openToday = UNNotificationAction(
            identifier: openTodayActionID,
            title: String(localized: "alert.action.openToday", defaultValue: "Ver Hoy"),
            options: [.foreground])
        let category = UNNotificationCategory(
            identifier: AlertNotification.categoryIdentifier, actions: [openToday], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func add(_ notification: AlertNotification, trigger: UNNotificationTrigger?) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.threadIdentifier
        content.categoryIdentifier = AlertNotification.categoryIdentifier
        if let coachingID = notification.coachingID {
            content.userInfo = [Self.coachingUserInfoKey: coachingID]
        }
        content.interruptionLevel = notification.isTimeSensitive ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }
}
