import Foundation
import LingoCore
import Observation

/// Registro rápido desde Hoy: elegir tipo (primer toque) y guardar (segundo toque). Escribe en el Diario por
/// `DiaryStore` con el mismo linaje que el editor completo (`edit_id`, `parent_edit_id` nulo en el alta).
@MainActor
@Observable
final class QuickAddModel: Identifiable {
    let id = UUID()
    /// Duración sugerida al elegir ejercicio, para que guardar siga siendo un toque.
    static let suggestedDurationMinutes = 30

    private(set) var kind: DiaryEventKind?
    var draft: DiaryDraft
    private(set) var savedCount = 0

    @ObservationIgnored private let diary: DiaryViewModel

    var isSaving: Bool { diary.isSaving }
    var didFailToSave: Bool { diary.failure == .saveFailed }
    var canSave: Bool { kind != nil && draft.isValid && !isSaving }

    /// - Parameter at: hora por defecto del registro (ahora).
    init(
        store: any DiaryStore,
        at: Date,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        diary = DiaryViewModel(store: store, calendar: calendar, now: now, newID: newID)
        draft = DiaryDraft(now: at)
    }

    func choose(_ newKind: DiaryEventKind) {
        kind = newKind
        draft.kind = newKind
        if newKind == .exercise, draft.durationText.isEmpty {
            draft.durationText = String(Self.suggestedDurationMinutes)
        }
    }

    /// Guarda y devuelve `true` si el evento quedó en el diario.
    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        let saved = await diary.save(draft, editing: nil)
        if saved { savedCount += 1 }
        return saved
    }
}
