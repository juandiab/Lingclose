import LingoCore
import SwiftUI

/// Hoja "Preguntar al asistente" (T-25): una petición al abrirla con el contexto agregado de la alerta, la respuesta
/// validada, la nota de no consejo médico, "Guardar como nota" y "Cerrar". Sin botón de reintentar: cada toque en la
/// tarjeta es un intento. Mientras pregunta no se cierra deslizando (la llamada puede costar); "Cerrar" la cancela.
struct CoachingAssistantSheet: View {
    let onNoteSaved: () -> Void

    @State private var model: CoachingAssistantViewModel
    @Environment(\.dismiss) private var dismiss

    init(record: CoachingRecord, assistant: any CoachingAsking, diary: any DiaryStore, onNoteSaved: @escaping () -> Void) {
        self.onNoteSaved = onNoteSaved
        _model = State(initialValue: CoachingAssistantViewModel(record: record, assistant: assistant, diary: diary))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .loading:
                    CoachingLoadingSection()
                case .failed(let message):
                    CoachingFailedSection(message: message)
                case .ready(let answer):
                    CoachingReplySections(answer: answer)
                    CoachingNoteSection(state: model.noteState, onSave: saveNote)
                }
                CoachingDisclaimerSection()
            }
            .navigationTitle(String(localized: "coaching.sheet.title", defaultValue: "Asistente"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Cerrar"), action: close)
                }
            }
            .task { await model.load() }
            .onDisappear(perform: model.cancel)
            .animation(.smooth, value: model.phase)
        }
        .interactiveDismissDisabled(model.phase == .loading)
        .presentationDetents([.large])
    }

    private func saveNote() {
        Task {
            if await model.saveNote() { onNoteSaved() }
        }
    }

    private func close() {
        model.cancel()
        dismiss()
    }
}

#Preview {
    let context = CoachingContext(kind: .high, value: 165, minutesSinceLastMeal: 40, hour: 14)
    CoachingAssistantSheet(
        record: CoachingRecord(id: "p", context: context, tipIDs: CoachingRules.tips(for: context).map(\.id),
                               createdAt: .now, openedAt: .now),
        assistant: PreviewCoachingAssistant(), diary: InMemoryDiaryStore()) {}
}
