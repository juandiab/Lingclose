import Foundation
import Synchronization
@testable import LingoScan

/// Reloj manual. `sleep` no avanza el tiempo: los tests llaman al vigilante directamente.
final class TestClock: SessionClock {
    private let current: Mutex<Date>

    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = Mutex(start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by duration: Duration) {
        current.withLock { $0 = $0.addingTimeInterval(duration.timeInterval) }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}
