import LingoCore
import SwiftUI

/// Diario: lista por día de comidas, ejercicio y notas, con un botón flotante de vidrio para añadir.
struct DiaryView: View {
    @Bindable var viewModel: DiaryViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    ContentUnavailableView(
                        String(localized: "diary.empty.title", defaultValue: "Sin registros"),
                        systemImage: "book.closed",
                        description: Text(String(localized: "diary.empty.description", defaultValue: "Toca + para anotar una comida, ejercicio o nota. Aparecen como marcas en la curva de Hoy."))
                    )
                } else {
                    list
                }
            }
            .navigationTitle(String(localized: "diary.title", defaultValue: "Diario"))
            .appBackground()
            .overlay(alignment: .bottomTrailing) { addButton }
        }
        // Carga al aparecer (también al volver a la pestaña) y sigue los cambios hechos desde Hoy.
        .task {
            await viewModel.load()
            await viewModel.observeChanges()
        }
        .sheet(item: $viewModel.editor) { editor in
            DiaryEditorView(viewModel: viewModel, editor: editor)
        }
        .diaryDeletionConfirmation(viewModel)
    }

    private var list: some View {
        List {
            if viewModel.failure == .loadFailed {
                Label(
                    String(localized: "diary.failure.load", defaultValue: "No se pudo leer el diario."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(Tokens.Palette.error)
            }
            ForEach(viewModel.days) { day in
                Section {
                    ForEach(day.events, id: \.eventID) { event in
                        Button {
                            viewModel.beginEdit(event)
                        } label: {
                            DiaryRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if viewModel.canModify(event) {
                                DiaryDeleteSwipeButton(viewModel: viewModel, event: event)
                            }
                        }
                    }
                } header: {
                    Text(day.start, format: .dateTime.weekday(.wide).day().month(.wide))
                }
            }
        }
        // Deja espacio para que el botón flotante no tape la última fila.
        .safeAreaPadding(.bottom, Tokens.Spacing.xl)
    }

    private var addButton: some View {
        Button {
            viewModel.beginAdd()
        } label: {
            Label(String(localized: "diary.add", defaultValue: "Añadir al diario"), systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .padding(Tokens.Spacing.sm)
    }
}

#Preview {
    DiaryView(viewModel: DiaryViewModel(store: InMemoryDiaryStore(events: PreviewData().events)))
}
