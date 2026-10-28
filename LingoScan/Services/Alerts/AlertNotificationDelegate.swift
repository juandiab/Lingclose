import Foundation
import UserNotifications

/// Delegado de `UNUserNotificationCenter`: muestra las alertas también con la app en primer plano y, al tocar la
/// notificación o "Ver Hoy", publica `openToday` para que la raíz seleccione la pestaña Hoy.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let openToday = Notification.Name("lingoscan.alerts.openToday")
    static let shared = AlertNotificationDelegate()

    /// Hay que instalarlo antes de terminar el arranque para recibir la respuesta que abrió la app.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
        AlertNotifier.registerCategories()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == AlertNotification.categoryIdentifier else { return }
        switch response.actionIdentifier {
        case AlertNotifier.openTodayActionID, UNNotificationDefaultActionIdentifier:
            await MainActor.run { NotificationCenter.default.post(name: Self.openToday, object: nil) }
        default:
            break
        }
    }
}
