import LingoCore
import SwiftUI

/// Registro del día mostrado en Hoy: comidas, ejercicio y notas, con edición y borrado (tombstone) por `DiaryViewModel`.
struct TodayEntriesView: View {
    let day: Date
    let calendar: Calendar
    @State private var diary: DiaryViewModel

    init(day: Date, store: any DiaryStore, calendar: Calendar) {
        self.day = day
        self.calendar = calendar
        _diary = State(initialValue: DiaryViewModel(store: store, calendar: calendar))
    }

    private var events: [DiaryEvent] {
        diary.days.first { calendar.isDate($0.start, inSameDayAs: day) }?.events ?? []
    }

    var body: some View {
        List {
            ForEach(events, id: \.eventID) { event in
                Button {
                    diary.beginEdit(event)
                } label: {
                    DiaryRow(event: event)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    if diary.canModify(event) {
                        Button(String(localized: "diary.delete.confirm", defaultValue: "Borrar"), systemImage: "trash", role: .destructive) {
                            diary.pendingDeletion = event
                        }
                    }
                }
            }
        }
        .overlay {
            if diary.hasLoaded && events.isEmpty {
                ContentUnavailableView(
                    String(localized: "diary.empty.title", defaultValue: "Sin registros"),
                    systemImage: "book.closed"
                )
            }
        }
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .task { await diary.load() }
        .sheet(item: $diary.editor) { editor in
            DiaryEditorView(viewModel: diary, editor: editor)
        }
        .confirmationDialog(
            String(localized: "diary.delete.title", defaultValue: "¿Borrar este registro?"),
            isPresented: $diary.isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: diary.pendingDeletion
        ) { event in
            Button(String(localized: "diary.delete.confirm", defaultValue: "Borrar"), role: .destructive) {
                Task { await diary.delete(event) }
            }
        } message: { _ in
            Text(String(localized: "diary.delete.message", defaultValue: "Se conserva el historial de ediciones; el registro deja de mostrarse."))
        }
    }
}
