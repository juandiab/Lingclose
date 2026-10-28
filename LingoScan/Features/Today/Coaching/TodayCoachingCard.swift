import SwiftUI

/// La tarjeta "Qué hacer" de Hoy si hay una alerta abierta desde su notificación (T-25); si no, nada.
struct TodayCoachingCard: View {
    let coaching: CoachingController?
    /// Alerta cuya pregunta al asistente se abre en una hoja.
    @Binding var askingRecord: CoachingRecord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let coaching, let record = coaching.record {
            CoachingCard(record: record, canAskAssistant: coaching.canAskAssistant, onAsk: ask, onDismiss: dismiss)
                .transition(.opacity)
        }
    }

    private func ask() {
        askingRecord = coaching?.record
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .smooth) { coaching?.dismiss() }
    }
}
