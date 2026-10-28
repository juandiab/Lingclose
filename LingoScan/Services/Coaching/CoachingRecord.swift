import Foundation
import LingoCore

/// La última alerta con consejos (T-25), guardada para la tarjeta "Qué hacer" de Hoy y para la pregunta opcional al
/// asistente. Solo agregados. Se reemplaza con la siguiente alerta; la tarjeta aparece cuando se tocó la notificación
/// y queda hasta que se cierra (o 12 h).
struct CoachingRecord: Codable, Sendable, Equatable, Identifiable {
    static let maxAge: TimeInterval = 12 * 3600

    /// Identificador de la notificación (`lingoscan.alert.<tipo>.<epoch>`).
    var id: String
    var context: CoachingContext
    /// Consejos de reglas mostrados (hasta 2), en orden.
    var tipIDs: [String]
    /// Nutrientes de la última comida, si la hubo.
    var mealNutrients: Nutrients?
    var exerciseKind: String?
    var exerciseDurationMin: Int?
    var createdAt: Date
    /// Cuándo se tocó la notificación; `nil` si no se ha abierto desde ella.
    var openedAt: Date?
    var isDismissed = false

    var tips: [CoachingTip] { tipIDs.compactMap(CoachingRules.tip(id:)) }

    func isVisible(at now: Date) -> Bool {
        openedAt != nil && !isDismissed && now.timeIntervalSince(createdAt) < Self.maxAge
    }
}
