import Testing
@testable import LingoCore

struct AlarmPolicyTests {
    static let t0 = UTCInstant(epochSeconds: 1_793_102_400)
    let settings = AlarmSettings.default

    func at(_ minutes: Int) -> UTCInstant { Self.t0.adding(seconds: Int64(minutes) * 60) }

    /// Alimenta una serie (minuto, valor) y devuelve las alarmas disparadas con su minuto.
    func run(_ series: [(Int, Int)], settings: AlarmSettings? = nil, state: AlarmState = AlarmState()) -> (fired: [(Int, AlarmKind)], state: AlarmState) {
        var state = state
        var fired: [(Int, AlarmKind)] = []
        for (minute, value) in series {
            let r = AlarmPolicy.evaluate(sample: AlarmSample(valueMgdl: value, measuredAt: at(minute)), now: at(minute),
                                         settings: settings ?? self.settings, state: state)
            state = r.state
            if case .fire(let kind, _) = r.decision { fired.append((minute, kind)) }
        }
        return (fired, state)
    }

    @Test func defaultsFollowD12() {
        #expect(settings.lowMgdl == 70 && settings.highMgdl == 180 && settings.noDataMinutes == 20)
    }

    @Test func highCrossingFiresOnceThenStaysQuiet() {
        let r = run([(0, 120), (1, 150), (2, 185), (3, 190), (4, 200)])
        #expect(r.fired.map(\.0) == [2])
        #expect(r.fired.map(\.1) == [.high])
    }

    @Test func lowCrossingFires() {
        let r = run([(0, 90), (1, 72), (2, 68), (3, 65)])
        #expect(r.fired.map(\.0) == [2])
        #expect(r.fired.map(\.1) == [.low])
    }

    @Test func valuesAtTheThresholdDoNotFire() {
        #expect(run([(0, 70), (1, 180)]).fired.isEmpty)
    }

    @Test func oscillationAroundThresholdDoesNotRepeatWithin15Minutes() {
        // 69, 71, 69, 71, 69... cada minuto: solo la primera.
        let series = (0..<12).map { ($0, $0 % 2 == 0 ? 69 : 71) }
        #expect(run(series).fired.map(\.0) == [0])
    }

    @Test func repeatsAfter15MinutesWhileStillOutOfRange() {
        let series = (0...31).map { ($0, 60) }
        #expect(run(series).fired.map(\.0) == [0, 15, 30])
    }

    @Test func returnAndReexitAfter15MinutesFiresAgain() {
        let r = run([(0, 60), (5, 100), (16, 60)])
        #expect(r.fired.map(\.0) == [0, 16])
    }

    @Test func lowAndHighHaveIndependentHysteresis() {
        let r = run([(0, 60), (1, 200)])
        #expect(r.fired.map(\.1) == [.low, .high])
    }

    @Test func disabledAlarmsStaySilent() {
        var s = settings
        s.lowEnabled = false
        #expect(run([(0, 50)], settings: s).fired.isEmpty)
        s.highEnabled = false
        #expect(run([(0, 300)], settings: s).fired.isEmpty)
    }

    @Test func noDataFiresAt20MinutesAfterLastValidReading() {
        let armed = run([(0, 100)]).state
        #expect(armed.lastValid == at(0))
        #expect(AlarmPolicy.noDataDeadline(lastValid: at(0), settings: settings) == at(20))
        #expect(AlarmPolicy.evaluateNoData(now: at(19), settings: settings, state: armed).decision == .none)
        let r = AlarmPolicy.evaluateNoData(now: at(20), settings: settings, state: armed)
        #expect(r.decision == .fire(.noData, valueMgdl: nil))
        // No se repite dentro de 15 min.
        #expect(AlarmPolicy.evaluateNoData(now: at(30), settings: settings, state: r.state).decision == .none)
        #expect(AlarmPolicy.evaluateNoData(now: at(35), settings: settings, state: r.state).decision == .fire(.noData, valueMgdl: nil))
    }

    @Test func noDataIsRearmedByEachValidReading() {
        let armed = run([(0, 100), (10, 100)]).state
        #expect(AlarmPolicy.evaluateNoData(now: at(20), settings: settings, state: armed).decision == .none)
        #expect(AlarmPolicy.evaluateNoData(now: at(30), settings: settings, state: armed).decision == .fire(.noData, valueMgdl: nil))
    }

    @Test func noDataWithoutAnyReadingOrWhenDisabledIsSilent() {
        #expect(AlarmPolicy.evaluateNoData(now: at(100), settings: settings, state: AlarmState()).decision == .none)
        var s = settings
        s.noDataEnabled = false
        let armed = run([(0, 100)]).state
        #expect(AlarmPolicy.evaluateNoData(now: at(30), settings: s, state: armed).decision == .none)
    }

    @Test func pausedStateSilencesEverything() {
        let paused = AlarmState().paused(true)
        let r = run([(0, 40), (1, 300)], state: paused)
        #expect(r.fired.isEmpty)
        #expect(AlarmPolicy.evaluateNoData(now: at(100), settings: settings, state: run([(0, 100)]).state.paused(true)).decision == .none)
        // Al reanudar parte sin "sin datos" pendiente hasta la siguiente lectura.
        let resumed = run([(0, 100)]).state.paused(true).paused(false)
        #expect(resumed.lastValid == nil)
        #expect(run([(5, 50)], state: resumed).fired.map(\.1) == [.low])
    }

    @Test func staleBackfilledSampleNeitherFiresNorArms() {
        let r = AlarmPolicy.evaluate(sample: AlarmSample(valueMgdl: 50, measuredAt: at(0)), now: at(60), settings: settings, state: AlarmState())
        #expect(r.decision == .none && r.state.lastValid == nil)
    }

    @Test func onlyEligibleLiveNonSyntheticReadingsBecomeSamples() {
        let session = TestSupport.session()
        let ok = TestSupport.reading(session, lc: 70, raw: TestSupport.raw(uncapped: 65, capped: 65, trend: 3), origin: .live)
        #expect(AlarmSample(reading: ok)?.valueMgdl == 65)
        let historic = TestSupport.reading(session, lc: 70, raw: TestSupport.raw(uncapped: 65, capped: 65), origin: .backfillHistory)
        #expect(AlarmSample(reading: historic) == nil)
        let synthetic = TestSupport.reading(session, lc: 70, raw: TestSupport.raw(uncapped: 65, capped: 65), origin: .live, synthetic: true)
        #expect(AlarmSample(reading: synthetic) == nil)
        let warmup = TestSupport.reading(session, lc: 5, raw: TestSupport.raw(uncapped: 65, capped: 65), origin: .live)
        #expect(AlarmSample(reading: warmup) == nil)
    }

    @Test func normalizedKeepsLowBelowHighAndInRange() {
        let s = AlarmSettings(lowMgdl: 500, highMgdl: 10, noDataMinutes: 1).normalized()
        #expect(s.lowMgdl == 120 && s.highMgdl == 121 && s.noDataMinutes == 10)
    }
}
