import LingoCore
import SwiftUI

/// Hoja del "+" de Hoy: tres botones grandes (Comida, Ejercicio, Nota); al elegir uno aparecen los campos
/// opcionales y "Guardar". Hora por defecto: ahora.
struct QuickAddSheet: View {
    let model: QuickAddModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var noteFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack(spacing: Tokens.Spacing.xs) {
                    ForEach(DiaryEventKind.creatable, id: \.self) { kind in
                        kindButton(kind)
                    }
                }
                if let kind = model.kind {
                    DatePicker(String(localized: "diary.editor.time", defaultValue: "Hora"), selection: $model.draft.at)
                    switch kind {
                    case .meal:
                        TextField(String(localized: "diary.editor.carbs", defaultValue: "Carbohidratos (g), opcional"), text: $model.draft.carbsText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    case .exercise:
                        TextField(String(localized: "diary.editor.duration", defaultValue: "Duración (min)"), text: $model.draft.durationText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    case .note, .sensorNote:
                        TextField(String(localized: "diary.editor.text.note", defaultValue: "Nota"), text: $model.draft.text, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                            .focused($noteFocused)
                    }
                    if kind != .note {
                        TextField(String(localized: "diary.editor.text.optional", defaultValue: "Descripción, opcional"), text: $model.draft.text)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                if model.didFailToSave {
                    Label(
                        String(localized: "diary.failure.save", defaultValue: "No se pudo guardar. Inténtalo de nuevo."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Tokens.Palette.error)
                }
                Spacer(minLength: 0)
                Button {
                    Task {
                        if await model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                } label: {
                    Text(String(localized: "common.save", defaultValue: "Guardar"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canSave)
            }
            .padding(Tokens.Spacing.sm)
            .navigationTitle(String(localized: "diary.editor.title.new", defaultValue: "Nuevo registro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancelar")) { dismiss() }
                }
            }
            .animation(.smooth, value: model.kind)
            .sensoryFeedback(.success, trigger: model.savedCount)
            .sensoryFeedback(.selection, trigger: model.kind)
        }
        .presentationDetents([.medium, .large])
    }

    private func kindButton(_ kind: DiaryEventKind) -> some View {
        let isSelected = model.kind == kind
        return Button {
            model.choose(kind)
            noteFocused = kind == .note
        } label: {
            VStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: kind.systemImage)
                    .font(.title)
                    .accessibilityHidden(true)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: .rect(cornerRadius: Tokens.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
