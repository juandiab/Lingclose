import Foundation
import Testing
@testable import LingoScan

/// Drenado automático a Health: debounce de avisos y drenado al volver a primer plano.
@MainActor
struct TodayHealthDrainTriggerTests {
    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    @Test func burstOfReadingsDrainsOnceAfterTheDebounce() async throws {
        let counter = Counter()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let trigger = HealthDrainTrigger(changes: stream, debounce: .milliseconds(150)) { await counter.increment() }
        continuation.yield()
        continuation.yield()
        continuation.yield()
        try await Task.sleep(for: .milliseconds(60))
        #expect(await counter.value == 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await counter.value == 1)
        withExtendedLifetime(trigger) {}
    }

    @Test func becomingActiveDrainsWithoutWaiting() async throws {
        let counter = Counter()
        let (stream, _) = AsyncStream.makeStream(of: Void.self)
        let trigger = HealthDrainTrigger(changes: stream, debounce: .seconds(30)) { await counter.increment() }
        trigger.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(150))
        #expect(await counter.value == 1)
    }
}
