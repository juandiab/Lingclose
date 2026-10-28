import Foundation
import Testing
@testable import LingoCore

struct AlertEvaluatorTests {
    /// 2026-10-28 12:00:00 UTC.
    static let t0 = UTCInstant(epochSeconds: 1_793_188_800)
    static let utc = TimeZone(identifier: "UTC")!
    let on = AlertSettings(isEnabled: true)

    func at(_ minute: Int) -> UTCInstant { Self.t0.adding(seconds: Int64(minute) * 60) }

    /// Simula una lectura por minuto: en cada minuto evalúa con las lecturas de los últimos 20 min.
    func run(_ values: [Int], from start: Int = 0, settings: AlertSettings? = nil, state: AlertState = AlertState(),
             low: Int = 70, high: Int = 140) -> (fired: [(Int, AlertKind)], events: [AlertEvent], state: AlertState) {
        var state = state
        var fired: [(Int, AlertKind)] = []
        var events: [AlertEvent] = []
        var all: [BasicStats.Sample] = []
        for (i, value) in values.enumerated() {
            let minute = start + i
            all.append(BasicStats.Sample(measuredAt: at(minute), valueMgdl: value))
            let window = all.filter { $0.measuredAt.epochSeconds > at(minute).epochSeconds - 20 * 60 }
            let r = AlertEvaluator.evaluate(samples: window, now: at(minute), low: low, high: high,
                                            settings: settings ?? on, state: state, timeZone: Self.utc)
            state = r.state
            fired += r.alerts.map { (minute, $0.kind) }
            events += r.alerts
        }
        return (fired, events, state)
    }

    @Test func defaults() {
        let d = AlertSettings.default
        #expect(!d.isEnabled)
        #expect(AlertKind.allCases.allSatisfy(d.isEnabled))
        #expect(d.rateThreshold == 2.0 && d.rateWindowMinutes == 15 && d.noDataAfterMinutes == 20)
        #expect(d.cooldown(for: .high) == 30 && d.cooldown(for: .noData) == 60)
        #expect(d.quietHours == nil && d.lowOverridesQuietHours)
    }

    @Test func highFiresOnceAndRespectsCooldown() {
        // Sube de 120 a 160 y se mantiene alta 40 min.
        var settings = on
        settings.setEnabled(false, for: .risingFast)
        let values = [120, 130, 150] + Array(repeating: 160, count: 40)
        let r = run(values, settings: settings)
        // Minuto 2: entra en alta. Minuto 32: recordatorio tras 30 min de silencio entre avisos.
        #expect(r.fired.map(\.0) == [2, 32])
        #expect(r.fired.allSatisfy { $0.1 == .high })
        #expect(r.events.first?.value == 150)
        #expect(r.events.first?.since == at(2))
        #expect(r.events.last?.since == at(2))
    }

    @Test func backInRangeThenOutFiresAgain() {
        // Alta, vuelve al rango (≤ 135 rearma), sale de nuevo a los 10 min: avisa aunque no pasaron 30 min.
        let values = [150, 150, 150, 120, 120, 120, 120, 120, 120, 120, 150]
        let r = run(values)
        #expect(r.fired.map(\.0) == [0, 10])
    }

    @Test func jitterAroundTheLineDoesNotRefire() {
        // 141 ↔ 138: no baja de 135, así que no se rearma.
        let values = [141, 138, 141, 138, 141, 138, 141]
        #expect(run(values).fired.map(\.0) == [0])
    }

    @Test func risingFastAtTwoPointFiveFires() {
        // 2,5 mg/dL/min desde 80: 16 lecturas (ventana de 15 min completa en el minuto 15); alta en 200 para aislar.
        let values = (0...15).map { 80 + Int(Double($0) * 2.5) }
        let r = run(values, high: 200)
        // Primer minuto con ≥ 3 lecturas en cada bloque de 5 min de la ventana: el 13.
        #expect(r.fired.map(\.1) == [.risingFast])
        #expect(r.fired.first?.0 == 13)
        let slope = r.events.first?.slopePerMinute ?? 0
        #expect(abs(slope - 2.5) < 0.1)
    }

    @Test func slowRiseAtOneDoesNotFire() {
        let values = (0...25).map { 80 + $0 }
        #expect(run(values, high: 200).fired.isEmpty)
    }

    @Test func fallingFastFires() {
        let values = (0...15).map { 180 - $0 * 3 }
        let r = run(values, low: 60, high: 250)
        #expect(r.fired.map(\.1) == [.fallingFast])
        #expect((r.events.first?.slopePerMinute ?? 0) < -2.5)
    }

    @Test func slopeIsFoldedIntoHighWhenBothFire() {
        // 103 + 3/min: en el minuto 13 (142) entra en alta y la ventana ya da pendiente. Un solo aviso, el de alta,
        // con la pendiente; la subida rápida cuenta como avisada.
        let values = (0...15).map { 103 + $0 * 3 }
        let r = run(values)
        #expect(r.fired.map(\.0) == [13])
        #expect(r.fired.map(\.1) == [.high])
        #expect((r.events.first?.slopePerMinute ?? 0) > 2.5)
        #expect(r.state.lastFired[.risingFast] == at(13))
    }

    @Test func quietHoursBlockHighButNotLow() {
        var settings = on
        settings.quietHours = QuietHours(startMinute: 11 * 60, endMinute: 13 * 60) // 11:00–13:00 UTC; t0 = 12:00
        #expect(run([160, 160], settings: settings).fired.isEmpty)
        #expect(run([60, 60], settings: settings).fired.map(\.1) == [.low])
        settings.lowOverridesQuietHours = false
        #expect(run([60, 60], settings: settings).fired.isEmpty)
    }

    @Test func highFiresWhenQuietHoursEnd() {
        var settings = on
        settings.quietHours = QuietHours(startMinute: 11 * 60, endMinute: 12 * 60 + 5) // termina a las 12:05
        let r = run(Array(repeating: 160, count: 8), settings: settings)
        #expect(r.fired.map(\.0) == [5])
        #expect(r.events.first?.since == at(0))
    }

    @Test func quietHoursAcrossMidnight() {
        let q = QuietHours.night
        #expect(q.contains(minuteOfDay: 23 * 60))
        #expect(q.contains(minuteOfDay: 6 * 60 + 59))
        #expect(!q.contains(minuteOfDay: 7 * 60))
        #expect(!q.contains(minuteOfDay: 12 * 60))
        #expect(!QuietHours(startMinute: 600, endMinute: 600).contains(minuteOfDay: 600))
    }

    @Test func noDataFiresAfterThresholdWithActiveSession() {
        let last = [BasicStats.Sample(measuredAt: at(0), valueMgdl: 110)]
        var state = AlertState()
        let early = AlertEvaluator.evaluate(samples: last, now: at(20), low: 70, high: 140, settings: on, state: state, timeZone: Self.utc)
        #expect(early.alerts.isEmpty)
        let late = AlertEvaluator.evaluate(samples: last, now: at(21), low: 70, high: 140, settings: on, state: early.state, timeZone: Self.utc)
        #expect(late.alerts.map(\.kind) == [.noData])
        #expect(late.alerts.first?.value == nil && late.alerts.first?.since == at(0))
        state = late.state
        // Dentro de los 60 min de silencio entre avisos no se repite; después, sí.
        let again = AlertEvaluator.evaluate(samples: [], now: at(60), low: 70, high: 140, settings: on, state: state,
                                            lastReadingAt: at(0), timeZone: Self.utc)
        #expect(again.alerts.isEmpty)
        let later = AlertEvaluator.evaluate(samples: [], now: at(82), low: 70, high: 140, settings: on, state: again.state,
                                            lastReadingAt: at(0), timeZone: Self.utc)
        #expect(later.alerts.map(\.kind) == [.noData])
    }

    @Test func noDataNeedsActiveSession() {
        let r = AlertEvaluator.evaluate(samples: [], now: at(60), low: 70, high: 140, settings: on, state: AlertState(),
                                        sessionActive: false, lastReadingAt: at(0), timeZone: Self.utc)
        #expect(r.alerts.isEmpty)
        #expect(!r.state.isActive(.noData))
    }

    @Test func staleReadingDoesNotFireHigh() {
        let old = [BasicStats.Sample(measuredAt: at(0), valueMgdl: 200)]
        let r = AlertEvaluator.evaluate(samples: old, now: at(6), low: 70, high: 140, settings: on, state: AlertState(), timeZone: Self.utc)
        #expect(r.alerts.isEmpty)
    }

    @Test func disabledSwitchesSilenceButTrackState() {
        var settings = on
        settings.setEnabled(false, for: .high)
        let r = run([160, 160], settings: settings)
        #expect(r.fired.isEmpty)
        #expect(r.state.isActive(.high))
        #expect(run([160, 160], settings: .default).fired.isEmpty)
    }

    @Test func assumingDeliveredBlocksRepeat() {
        let state = AlertState().assumingDelivered(.noData, at: at(20), since: at(0))
        let r = AlertEvaluator.evaluate(samples: [], now: at(25), low: 70, high: 140, settings: on, state: state,
                                        lastReadingAt: at(0), timeZone: Self.utc)
        #expect(r.alerts.isEmpty)
    }

    @Test func settingsAndStateRoundTripAsJSON() throws {
        var settings = AlertSettings(isEnabled: true, rateThreshold: 3.5, quietHours: .night)
        settings.setEnabled(false, for: .risingFast)
        settings.setCooldown(15, for: .high)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AlertSettings.self, from: data) == settings)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"risingFast\":false"))
        // Campos ausentes toman el valor por defecto.
        let partial = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(partial.isEnabled && partial.rateThreshold == 2.0 && partial.noDataAfterMinutes == 20)
        let state = AlertState(lastFired: [.high: at(3)], activeSince: [.high: at(1)])
        #expect(try JSONDecoder().decode(AlertState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func normalizedClampsEditableValues() {
        let s = AlertSettings(rateThreshold: 7.3, noDataAfterMinutes: 3).normalized()
        #expect(s.rateThreshold == 4.0 && s.noDataAfterMinutes == 10)
        #expect(AlertSettings(rateThreshold: 2.3).normalized().rateThreshold == 2.5)
    }

    @Test func localMinuteUsesTimeZone() {
        let bogota = TimeZone(identifier: "America/Bogota")!
        #expect(AlertEvaluator.localMinute(of: Self.t0, in: Self.utc) == 12 * 60)
        #expect(AlertEvaluator.localMinute(of: Self.t0, in: bogota) == 7 * 60)
    }
}
