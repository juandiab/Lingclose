import Foundation
import Testing
@testable import LingoCore

/// `ReportSnapshot` (T-27a): JSON estable, snake_case, sin datos identificables y compactable.
struct ReportsSnapshotTests {
    private typealias F = ReportsFixture

    /// Período con comidas (3 al día) y un ejercicio diario, con textos e ids que no deben salir.
    static func busyBundle(days: Int) -> ReportBundle {
        let first = F.local("2026-07-01", 0)
        let period = ReportPeriod(start: first, end: first.adding(seconds: Int64(days) * 86_400), timeZone: F.bogota)
        var meals: [UTCInstant] = []
        var events: [DiaryEvent] = []
        for d in 0..<days {
            let day = first.adding(seconds: Int64(d) * 86_400)
            for hour in [7, 13, 19] {
                let at = day.adding(seconds: Int64(hour) * 3600)
                meals.append(at)
                events.append(F.event(.meal, at: at, carbs: Double(20 + 10 * (d % 6)), text: "Plato secreto \(d)",
                                      id: "meal-secret-\(d)-\(hour)"))
            }
            events.append(F.event(.exercise, at: day.adding(seconds: 17 * 3600), duration: 30 + d % 40,
                                  text: "Ruta secreta", id: "exercise-secret-\(d)"))
            events.append(F.event(.note, at: day.adding(seconds: 10 * 3600), text: "Nota privada", id: "note-secret-\(d)"))
        }
        let samples = F.series(period) { t in F.minutesSinceLast(meals, t).map(F.mealCurve) ?? 100 }
        return ReportBuilder.build(samples: samples, events: events, period: period)
    }

    @Test func jsonHasStableSnakeCaseKeysAndNoPrivateData() throws {
        let bundle = Self.busyBundle(days: 7)
        let data = try bundle.snapshot.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["secret", "secreto", "privada", "Ruta", "America/", "Bogota", "time_zone", "event_id",
                          "session_id", "serial", "text", TestSupport.appID] {
            #expect(!text.contains(forbidden), "el snapshot no debe contener \(forbidden)")
        }
        var keys = Set<String>()
        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                for (key, child) in object { keys.insert(key); collect(child) }
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        collect(try JSONSerialization.jsonObject(with: data))
        let bad = keys.filter { key in !key.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" } }
        #expect(bad.isEmpty, "claves no snake_case: \(bad.sorted())")
        for expected in ["format_version", "period", "configuration", "summary", "hourly_profile", "weekly_comparison",
                         "meals", "nights", "exercise", "time_of_day", "series", "compaction", "time_in_range",
                         "utc_offset_minutes", "carbs_g", "time_to_peak_min", "interval_minutes", "by_slot", "by_carbs",
                         "by_duration", "low_episodes", "fast_rises_per_day"] {
            #expect(keys.contains(expected), "falta la clave \(expected)")
        }
        #expect(!keys.contains("daily_overlay"))
    }

    @Test func roundTripsAndIsByteStable() throws {
        let snapshot = Self.busyBundle(days: 7).snapshot
        let data = try snapshot.jsonData()
        let decoded = try ReportSnapshot.decode(data)
        #expect(decoded == snapshot)
        #expect(try decoded.jsonData() == data)
        #expect(snapshot.formatVersion == 1 && snapshot.period.days == 7 && snapshot.period.utcOffsetMinutes == -300)
        #expect(snapshot.compaction == .none)
        // El bundle completo también es Codable.
        let bundle = Self.busyBundle(days: 2)
        #expect(try JSONDecoder().decode(ReportBundle.self, from: JSONEncoder().encode(bundle)) == bundle)
    }

    @Test func compactFitsNinetyDaysAndKeepsAggregates() throws {
        let bundle = Self.busyBundle(days: 90)
        #expect(bundle.series.intervalMinutes == 15)
        let full = bundle.snapshot
        let compact = full.compact()
        let size = try compact.jsonData().count
        print("T-27a SNAPSHOT: 90 días completo \(try full.jsonData().count) B → compacto \(size) B (\(compact.compaction.rawValue))")
        #expect(size <= ReportSnapshot.defaultMaxBytes)
        #expect(compact.compaction != .none)
        #expect(compact.meals.overall == full.meals.overall && compact.nights.summary == full.nights.summary)
        #expect(compact.summary.stats == full.summary.stats && compact.hourlyProfile == full.hourlyProfile)

        // Un período corto cabe tal cual.
        let small = Self.busyBundle(days: 3).snapshot
        #expect(small.compact() == small)

        // Con un límite imposible llega al último paso y conserva los agregados.
        let tiny = full.compact(maxBytes: 100)
        #expect(tiny.compaction == .detailsRemoved && tiny.series == nil && tiny.meals.meals.isEmpty)
        #expect(tiny.meals.overall == full.meals.overall)
    }

    @Test func downsamplingAveragesNonNilValues() {
        let series = ResampledSeries(start: F.instant("2026-10-01T00:00:00Z"), intervalMinutes: 5,
                                     values: [100, nil, 110, nil, nil, nil, 90])
        let coarse = series.downsampled(by: 3)
        #expect(coarse.intervalMinutes == 15 && coarse.values == [105, nil, 90])
    }
}
