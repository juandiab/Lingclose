import Foundation
import LingoCore

/// Lo que el Diario necesita de la base: leer eventos no borrados y guardar una versión nueva (con linaje).
protocol DiaryStore: Sendable {
    /// Eventos con `at` dentro del rango, sin los tombstones.
    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent]
    /// Guarda una versión de un evento. El linaje (`edit_id` → `parent_edit_id`) viaja en el propio evento.
    func save(_ event: DiaryEvent) async throws
}

/// Diario sobre `SQLiteStore`: `upsertEvent` aplica el linaje de ediciones del contrato §5.3.
struct SQLiteDiaryStore: DiaryStore {
    let store: SQLiteStore

    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        try await store.events(in: range)
    }

    func save(_ event: DiaryEvent) async throws {
        try await store.upsertEvent(event)
    }
}
