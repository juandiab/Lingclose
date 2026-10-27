import Foundation
import Testing
@testable import LingoCore

struct PerformanceTests {
    @Test func twentyThousandReadingsRangeQueryUnder50ms() async throws {
        let store = try TestSupport.makeStore()
        let session = TestSupport.session()
        try await store.upsertSession(session)
        let readings = (0..<20_000).map { lc in
            TestSupport.reading(session, lc: lc, raw: TestSupport.raw(uncapped: 70 + lc % 150, capped: 70 + lc % 150,
                                                                    trend: 3, temperature: 3200, channel: 1), origin: .live)
        }
        let clock = ContinuousClock()
        let insertTime = try await clock.measure { try await store.insertReadings(readings) }
        #expect(try await store.readingCount() == 20_000)

        // Ventana de 24 h (1 440 lecturas) y rango completo (20 000).
        let dayFrom = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: 10_000)
        let dayTo = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: 11_439)
        let allFrom = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: 0)
        let allTo = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: 19_999)

        var dayTimes: [Duration] = []
        var allTimes: [Duration] = []
        var dayCount = 0, allCount = 0
        for _ in 0..<5 {
            dayTimes.append(try await clock.measure { dayCount = try await store.readings(in: dayFrom...dayTo).count })
            allTimes.append(try await clock.measure { allCount = try await store.readings(in: allFrom...allTo).count })
        }
        #expect(dayCount == 1_440)
        #expect(allCount == 20_000)
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        let line = String(format: "T-07 PERF: insert 20000 en transacción %.1f ms; rango 24 h (1440) primera %.2f ms, mínima %.2f ms; rango completo (20000) primera %.2f ms, mínima %.2f ms",
                          ms(insertTime), ms(dayTimes[0]), ms(dayTimes.min()!), ms(allTimes[0]), ms(allTimes.min()!))
        print(line)
        // Ventana de UI (3/6/24 h): < 50 ms en cualquier configuración.
        #expect(ms(dayTimes[0]) < 50, "\(line)")
        // Rango completo de 20 000: < 50 ms optimizado; en debug sin optimizar se admite hasta 100 ms.
        #if DEBUG
        #expect(ms(allTimes.min()!) < 100, "\(line)")
        #else
        #expect(ms(allTimes.min()!) < 50, "\(line)")
        #endif
    }
}
