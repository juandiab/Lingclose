import Foundation
import LingoCore

/// Adaptador real de Hoy sobre `SQLiteStore`. Avisa de datos nuevos cada vez que el
/// coordinador cambia de estado (cada lectura en vivo produce un `streaming` nuevo).
struct LiveTodayDataSource: TodayDataSource {
    let store: SQLiteStore
    let coordinator: SensorSessionCoordinator?
    var clock: @Sendable () -> Date = { .now }

    /// Ventanas crecientes para buscar la última lectura elegible sin leer toda la base.
    static let latestLookbacks: [TimeInterval] = [6 * 3_600, 24 * 3_600, 15 * 86_400]

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        try await store.readings(in: range)
    }

    func latestEligibleReading() async throws -> GlucoseReading? {
        let end = clock()
        for lookback in Self.latestLookbacks {
            let range = UTCInstant(end.addingTimeInterval(-lookback))...UTCInstant(end)
            let latest = try await store.readings(in: range)
                .filter { $0.eligibility.isEligible && $0.value != nil }
                .max { $0.measuredAt < $1.measuredAt }
            if let latest { return latest }
        }
        return nil
    }

    func diaryEvents(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        try await store.events(in: range)
    }

    func changes() -> AsyncStream<Void> {
        guard let coordinator else { return AsyncStream { $0.finish() } }
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                var isFirst = true
                for await _ in await coordinator.states() {
                    // El primer valor es el estado actual: la vista ya hace su carga inicial.
                    if isFirst { isFirst = false; continue }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
