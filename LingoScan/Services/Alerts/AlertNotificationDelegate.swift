import Foundation
import UserNotifications

/// Delegado de `UNUserNotificationCenter`: muestra las alertas también con la app en primer plano y, al tocar la
/// notificación o "Ver Hoy", publica `openToday` para que la raíz seleccione la pestaña Hoy (y, si la alerta traía
/// consejos, marca la `CoachingRecord` como abierta para que Hoy muestre "Qué hacer").
///
/// Variantes con `completionHandler`, no `async`: UIKit exige que el handler de `didReceive` se llame en el hilo
/// principal (si no, aborta con una aserción al actualizar la captura de la app; seis cierres el 28-oct). Con la
/// variante `async` el handler lo llama el ejecutor donde termina el método, que no es el principal, y la
/// implementación no puede aislarse a `@MainActor` porque `UNUserNotificationCenter` no es `Sendable`.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let openToday = Notification.Name("lingoscan.alerts.openToday")
    static let shared = AlertNotificationDelegate()

    /// Hay que instalarlo antes de terminar el arranque para recibir la respuesta que abrió la app.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
        AlertNotifier.registerCategories()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let opensToday = content.categoryIdentifier == AlertNotification.categoryIdentifier
            && (response.actionIdentifier == AlertNotifier.openTodayActionID
                || response.actionIdentifier == UNNotificationDefaultActionIdentifier)
        // T-25: la alerta traía consejos → la tarjeta "Qué hacer" aparece al abrir Hoy.
        let coachingID = opensToday ? content.userInfo[AlertNotifier.coachingUserInfoKey] as? String : nil
        let completion = MainThreadCompletion(completionHandler)
        DispatchQueue.main.async {
            if opensToday {
                if let coachingID { CoachingStore.appGroup().markOpened(id: coachingID, at: .now) }
                NotificationCenter.default.post(name: Self.openToday, object: nil)
            }
            completion.call()
        }
    }
}

/// Envuelve el `completionHandler` (bloque ObjC sin anotación `Sendable`) para llevarlo al hilo principal.
/// Se llama una sola vez; el bloque de UIKit es seguro de invocar desde cualquier hilo.
private struct MainThreadCompletion: @unchecked Sendable {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func call() { handler() }
}
