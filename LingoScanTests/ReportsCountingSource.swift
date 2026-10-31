import Foundation
import LingoCore
import Synchronization
@testable import LingoScan

/// Fuente de Reportes para pruebas: delega en otra, cuenta las lecturas pedidas y puede fallar a demanda.
final class ReportsCountingSource: ReportsDataSource {
    private let base: any ReportsDataSource
    private let state = Mutex((readingCalls: 0, fails: false))

    init(base: any ReportsDataSource) {
        self.base = base
    }

    var isSynthetic: Bool { base.isSynthetic }
    var readingCalls: Int { state.withLock { $0.readingCalls } }

    func setFailing(_ fails: Bool) {
        state.withLock { $0.fails = fails }
    }

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        let fails = state.withLock { state in
            state.readingCalls += 1
            return state.fails
        }
        if fails { throw ReportsCountingSourceError.unavailable }
        return try await base.readings(in: range)
    }

    func events(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        try await base.events(in: range)
    }
}
