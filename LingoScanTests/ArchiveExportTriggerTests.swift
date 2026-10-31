import Foundation
import LingoCore
import Synchronization
import Testing
@testable import LingoScan

@MainActor
struct ArchiveExportTriggerTests {
    /// Reloj del disparador sobre el mismo reloj manual del servicio. `sleep` no avanza: los tests llaman a `check`.
    struct HarnessClock: SessionClock {
        let base: ArchiveServiceTests.Clock
        var now: Date { base.now }
        func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3600)) }
    }

    /// El primer `sleep` (el `initialDelay`) vuelve en el acto avanzando el reloj; los siguientes esperan (cancelables).
    final class FirstSleepClock: SessionClock {
        let base: ArchiveServiceTests.Clock
        private let sleeps = Mutex<[Duration]>([])
        init(base: ArchiveServiceTests.Clock) { self.base = base }
        var now: Date { base.now }
        var recorded: [Duration] { sleeps.withLock { $0 } }
        func sleep(for duration: Duration) async throws {
            let isFirst = sleeps.withLock { $0.append(duration); return $0.count == 1 }
            if isFirst {
                base.advance(duration.timeInterval)
                return
            }
            try await Task.sleep(for: .seconds(3600))
        }
    }

    static func make(lastExportHoursAgo hours: TimeInterval) async throws -> (ArchiveServiceTests.Harness, ArchiveExportTrigger) {
        let h = try await prepared(lastExportHoursAgo: hours)
        let trigger = ArchiveExportTrigger(service: h.service, store: h.store, clock: HarnessClock(base: h.clock))
        return (h, trigger)
    }

    static func prepared(lastExportHoursAgo hours: TimeInterval) async throws -> ArchiveServiceTests.Harness {
        let h = try await ArchiveServiceTests.makeHarness()
        _ = try #require(await h.service.exportNow())
        h.clock.advance(hours * 3600)
        return h
    }

    /// Instala el disparador y espera (como mucho 10 s) a que termine la comprobación inicial.
    static func installAndAwaitInitialCheck(_ h: ArchiveServiceTests.Harness) async throws -> (ArchiveExportTrigger, FirstSleepClock) {
        let clock = FirstSleepClock(base: h.clock)
        let trigger = ArchiveExportTrigger(service: h.service, store: h.store, clock: clock, initialDelay: .seconds(120))
        trigger.install()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while trigger.completedChecks == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        trigger.stop()
        return (trigger, clock)
    }

    static func ownPackages(_ h: ArchiveServiceTests.Harness) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: h.fallback.path)
            .filter { $0.hasSuffix(".lingoscan") && $0.contains("-lingoscan-") }
    }

    static func dueLines(_ h: ArchiveServiceTests.Harness) async throws -> [EventLogEntry] {
        try await h.store.recentLogEvents(limit: 500)
            .filter { $0.category == "archive" && $0.message.contains("copia diaria vencida") }
    }

    @Test func tickWithOldCopyExportsOnce() async throws {
        let (h, trigger) = try await Self.make(lastExportHoursAgo: 30)
        #expect(try Self.ownPackages(h).count == 1)
        await trigger.check(.tick)
        #expect(try Self.ownPackages(h).count == 2)
        let lines = try await Self.dueLines(h)
        #expect(lines.count == 1)
        #expect(lines.first?.level == .info)
        // La copia nueva es reciente: el siguiente tick no vuelve a exportar ni a registrar.
        await trigger.check(.tick)
        #expect(try Self.ownPackages(h).count == 2)
        #expect(try await Self.dueLines(h).count == 1)
    }

    @Test func tickWithRecentCopyDoesNotExport() async throws {
        let (h, trigger) = try await Self.make(lastExportHoursAgo: 2)
        await trigger.check(.tick)
        #expect(try Self.ownPackages(h).count == 1)
        #expect(try await Self.dueLines(h).isEmpty)
    }

    @Test func twoTicksWithRecentCopyDoNotExport() async throws {
        let (h, trigger) = try await Self.make(lastExportHoursAgo: 2)
        await trigger.check(.tick)
        h.clock.advance(3600)
        await trigger.check(.tick)
        #expect(try Self.ownPackages(h).count == 1)
        #expect(try await Self.dueLines(h).isEmpty)
    }

    @Test func becomingActiveWithOldCopyExports() async throws {
        let (h, trigger) = try await Self.make(lastExportHoursAgo: 30)
        await trigger.sceneDidBecomeActive().value
        #expect(try Self.ownPackages(h).count == 2)
        #expect(try await Self.dueLines(h).count == 1)
    }

    @Test func failedExportIsNotRetriedByTicksWithinAnHourButIsOnActive() async throws {
        // Destino que deja de existir: el servicio no puede escribir el paquete.
        let (h, trigger) = try await Self.make(lastExportHoursAgo: 30)
        try FileManager.default.removeItem(at: h.fallback)
        try Data("archivo, no carpeta".utf8).write(to: h.fallback)
        await trigger.check(.tick)
        let failures = { try await h.store.recentLogEvents(limit: 500).filter { $0.message.contains("exportación fallida") }.count }
        let afterFirst = try await failures()
        #expect(afterFirst == 1)
        h.clock.advance(30 * 60)
        await trigger.check(.tick)
        #expect(try await failures() == afterFirst, "dentro de la hora un tick no reintenta")
        await trigger.sceneDidBecomeActive().value
        #expect(try await failures() == afterFirst + 1, "el siguiente .active sí reintenta")
    }

    @Test func initialCheckAfterLaunchDelayExportsOldCopyOnce() async throws {
        let h = try await Self.prepared(lastExportHoursAgo: 30)
        let (trigger, clock) = try await Self.installAndAwaitInitialCheck(h)
        #expect(trigger.completedChecks == 1)
        #expect(clock.recorded.first == .seconds(120), "la primera espera es el initialDelay, no la hora")
        #expect(try Self.ownPackages(h).count == 2)
        #expect(try await Self.dueLines(h).count == 1)
    }

    @Test func initialCheckAfterLaunchDelayKeepsRecentCopy() async throws {
        let h = try await Self.prepared(lastExportHoursAgo: 2)
        let (trigger, clock) = try await Self.installAndAwaitInitialCheck(h)
        #expect(trigger.completedChecks == 1)
        #expect(clock.recorded.first == .seconds(120))
        #expect(try Self.ownPackages(h).count == 1)
        #expect(try await Self.dueLines(h).isEmpty)
    }
}
