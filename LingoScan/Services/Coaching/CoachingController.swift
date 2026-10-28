import Foundation
import Observation

/// Estado de la tarjeta "Qué hacer" de Hoy (T-25): la última alerta con consejos, si se abrió tocando su notificación
/// y no se ha cerrado, y si hay asistente configurado para el botón "Preguntar al asistente".
@MainActor
@Observable
final class CoachingController {
    /// La alerta visible en Hoy, o `nil`.
    private(set) var record: CoachingRecord?
    private(set) var canAskAssistant = false

    @ObservationIgnored let assistant: any CoachingAsking
    @ObservationIgnored private let store: CoachingStore
    @ObservationIgnored private let now: @Sendable () -> Date

    init(store: CoachingStore, assistant: any CoachingAsking, now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.assistant = assistant
        self.now = now
    }

    /// Relee la última alerta (al abrir Hoy, al volver a primer plano y al tocar una notificación).
    func refresh() async {
        let latest = store.latest()
        let visible = latest?.isVisible(at: now()) == true ? latest : nil
        let configured = visible == nil ? false : await assistant.isConfigured()
        record = visible
        canAskAssistant = configured
    }

    /// Cierra la tarjeta hasta la siguiente alerta.
    func dismiss() {
        guard let record else { return }
        store.dismiss(id: record.id)
        self.record = nil
        canAskAssistant = false
    }
}
