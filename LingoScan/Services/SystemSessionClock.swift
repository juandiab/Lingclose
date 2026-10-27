import Foundation

struct SystemSessionClock: SessionClock {
    var now: Date { .now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
