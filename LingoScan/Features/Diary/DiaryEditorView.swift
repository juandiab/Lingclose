import LingoCore
import SwiftUI

/// Hoja de alta y edición. Alta en dos toques: "+" y "Guardar" (tipo comida, hora de ahora; el texto es opcional
/// salvo en las notas).
struct DiaryEditorView: View {
    let viewModel: DiaryViewModel
    let editor: DiaryEditor
    @State private var draft: DiaryDraft
    @State private var mode: Mode
    @State private var analysis: MealAnalysisViewModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mealAssistant) private var services

    /// Una comida con fila de nutrición se reabre con la pantalla de propuesta; el resto usa este formulario.
    private enum Mode {
        case loading
        case plain
        case reopened(MealAnalysisViewModel)
    }

    init(viewModel: DiaryViewModel, editor: DiaryEditor) {
        self.viewModel = viewModel
        self.editor = editor
        _draft = State(initialValue: editor.draft)
        _mode = State(initialValue: editor.editing?.kind == .meal ? .loading : .plain)
    }

    var body: some View {
        Group {
            switch mode {
            case .loading:
                ProgressView()
            case .plain:
                form
            case .reopened(let model):
                MealAnalysisView(model: model) {
                    Task { await viewModel.reloadAfterExternalSave() }
                }
            }
        }
        .task { await loadMealNutrition() }
    }

    private func loadMealNutrition() async {
        guard case .loading = mode, let event = editor.editing else { return }
        let record = try? await services.nutrition.mealNutrition(eventID: event.eventID)
        if let record {
            mode = .reopened(MealAnalysisViewModel(reopening: event, record: record, services: services))
        } else {
            mode = .plain
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "diary.editor.kind", defaultValue: "Tipo"), selection: $draft.kind) {
                        ForEach(kinds, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(editor.editing != nil)
                    DatePicker(String(localized: "diary.editor.time", defaultValue: "Hora"), selection: $draft.at)
                }
                Section {
                    switch draft.kind {
                    case .meal:
                        Button(String(localized: "meal.analyzeWithAI", defaultValue: "Analizar con IA…"), systemImage: "sparkles") {
                            analysis = MealAnalysisViewModel(
                                services: services, editing: editor.editing, at: draft.at, initialDescription: draft.trimmedText)
                        }
                        TextField(String(localized: "diary.editor.carbs", defaultValue: "Carbohidratos (g), opcional"), text: $draft.carbsText)
                            .keyboardType(.decimalPad)
                    case .exercise:
                        TextField(String(localized: "diary.editor.duration", defaultValue: "Duración (min)"), text: $draft.durationText)
                            .keyboardType(.numberPad)
                    case .note, .sensorNote:
                        EmptyView()
                    }
                    TextField(textPrompt, text: $draft.text, axis: .vertical)
                        .lineLimit(1...5)
                } footer: {
                    if let message = problemText {
                        Text(message)
                            .foregroundStyle(Tokens.Palette.error)
                    }
                }
                if viewModel.failure == .saveFailed {
                    Section {
                        Label(
                            String(localized: "diary.failure.save", defaultValue: "No se pudo guardar. Inténtalo de nuevo."),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(Tokens.Palette.error)
                    }
                }
            }
            .navigationTitle(editor.editing == nil
                ? String(localized: "diary.editor.title.new", defaultValue: "Nuevo registro")
                : String(localized: "diary.editor.title.edit", defaultValue: "Editar registro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancelar")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save", defaultValue: "Guardar")) {
                        Task { await viewModel.save(draft, editing: editor.editing) }
                    }
                    .disabled(!draft.isValid || viewModel.isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $analysis) { analysis in
            MealAnalysisView(model: analysis) {
                Task { await viewModel.reloadAfterExternalSave() }
            }
        }
    }

    private var kinds: [DiaryEventKind] {
        editor.editing.map { [$0.kind] } ?? DiaryEventKind.creatable
    }

    private var textPrompt: String {
        draft.kind == .note
            ? String(localized: "diary.editor.text.note", defaultValue: "Nota")
            : String(localized: "diary.editor.text.optional", defaultValue: "Descripción, opcional")
    }

    private var problemText: String? {
        switch draft.problem {
        case .carbsOutOfRange: String(localized: "diary.problem.carbs", defaultValue: "Los carbohidratos deben ser entre 0 y 1000 g.")
        case .durationMissing: String(localized: "diary.problem.duration", defaultValue: "Indica la duración en minutos (1 a 1440).")
        case .noteIsEmpty: String(localized: "diary.problem.note", defaultValue: "Escribe el texto de la nota.")
        case nil: nil
        }
    }
}
