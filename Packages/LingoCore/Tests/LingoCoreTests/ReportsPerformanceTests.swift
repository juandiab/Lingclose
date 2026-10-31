import Foundation
import Testing
@testable import LingoCore

/// Rendimiento del motor de reportes (T-27a): 90 días × 1 440 lecturas en menos de 1 s.
struct ReportsPerformanceTests {
    private typealias F = ReportsFixture

    @Test func ninetyDaysOfMinuteReadingsUnderOneSecond() throws {
        let first = F.local("2026-07-01", 0)
        let period = ReportPeriod(start: first, end: first.adding(seconds: 90 * 86_400), timeZone: F.bogota)
        var events: [DiaryEvent] = []
        for d in 0..<90 {
            let day = first.adding(seconds: Int64(d) * 86_400)
            for hour in [7, 13, 19] { events.append(F.event(.meal, at: day.adding(seconds: Int64(hour) * 3600), carbs: 40)) }
            events.append(F.event(.exercise, at: day.adding(seconds: 17 * 3600), duration: 40))
        }
        // Onda diaria con ruido determinista: 129 600 lecturas.
        let samples = F.series(period) { t in
            let m = Double(t.epochSeconds / 60)
            return 110 + Int(40 * sin(m / 1440 * 2 * .pi * 3)) + Int(t.epochSeconds / 60 % 7) - 3
        }
        #expect(samples.count == 90 * 1440)

        let clock = ContinuousClock()
        var bundle: ReportBundle?
        let elapsed = clock.measure { bundle = ReportBuilder.build(samples: samples, events: events, period: period) }
        let snapshotTime = try clock.measure { _ = try bundle?.snapshot.compact().jsonData() }
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        print(String(format: "T-27a PERF: build 90 días × 1440 lecturas (%d) %.1f ms; snapshot compacto %.1f ms",
                     samples.count, ms(elapsed), ms(snapshotTime)))
        let result = try #require(bundle)
        #expect(result.summary.stats.readings == 90 * 1440 && result.meals.meals.count == 270)
        // Objetivo: < 1 s optimizado (en release mide ≈ 25 ms). En debug sin optimizar `RateOfChange` domina
        // (≈ 1 s solo, ≈ 3 s con el resto de la suite en paralelo); se admite hasta 6 s para no dar falsos fallos.
        #if DEBUG
        #expect(ms(elapsed) < 6000, "build tardó \(ms(elapsed)) ms en debug")
        #else
        #expect(ms(elapsed) < 1000, "build tardó \(ms(elapsed)) ms")
        #endif
    }
}
