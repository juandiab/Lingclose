import SwiftUI

/// "Guardar como nota": crea un evento `note` del diario con la respuesta, una vez.
struct CoachingNoteSection: View {
    let state: CoachingAssistantViewModel.NoteState
    let onSave: () -> Void

    var body: some View {
        Section {
            Button(action: onSave) {
                switch state {
                case .saved:
                    Label(String(localized: "coaching.sheet.note.saved", defaultValue: "Guardada en el diario"), systemImage: "checkmark")
                case .saving:
                    Label(String(localized: "coaching.sheet.note.saving", defaultValue: "Guardando…"), systemImage: "square.and.arrow.down")
                case .idle, .failed:
                    Label(String(localized: "coaching.sheet.note.save", defaultValue: "Guardar como nota"), systemImage: "note.text.badge.plus")
                }
            }
            .disabled(state == .saving || state == .saved)
            if state == .failed {
                Text(String(localized: "coaching.sheet.note.failed", defaultValue: "No se pudo guardar la nota."))
                    .font(.footnote)
                    .foregroundStyle(Tokens.Palette.error)
            }
        }
        .sensoryFeedback(.success, trigger: state) { _, new in new == .saved }
    }
}
