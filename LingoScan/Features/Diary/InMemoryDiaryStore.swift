import Foundation
import LingoCore

/// Diario en memoria: previsualización (`PreviewData`) y pruebas. Conserva todas las versiones guardadas.
actor InMemoryDiaryStore: DiaryStore {
    private var current: [String: DiaryEvent] = [:]
    private(set) var history: [DiaryEvent] = []
    private(set) var failNextSave = false

    init(events: [DiaryEvent] = []) {
        for event in events { current[event.eventID] = event }
        history = events
    }

    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        current.values.filter { !$0.deleted && range.contains($0.at) }.sorted { $0.at < $1.at }
    }

    func save(_ event: DiaryEvent) async throws {
        if failNextSave {
            failNextSave = false
            throw InMemoryDiaryStoreError.simulatedFailure
        }
        current[event.eventID] = event
        history.append(event)
    }

    /// Todas las versiones de un evento, de la más antigua a la más nueva.
    func versions(of eventID: String) -> [DiaryEvent] {
        history.filter { $0.eventID == eventID }
    }

    func setFailNextSave(_ value: Bool) { failNextSave = value }
}

enum InMemoryDiaryStoreError: Error {
    case simulatedFailure
}
