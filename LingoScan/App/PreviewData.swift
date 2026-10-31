import Foundation
import LingoCore

/// Datos sintéticos para `#Preview`, pruebas y el arranque con `-previewSensorState` (DEBUG).
///
/// Sesión de 3 días marcada `synthetic: true` con una curva simulada (comidas, una desconexión de
/// 25 minutos, un tramo con bandera de calidad y el calentamiento inicial) más los vectores públicos
/// de Juggluco (`docs/PROTOCOLO_LINGO.md` §8) convertidos a `GlucoseReading` en una sesión anterior.
/// Nunca se exporta a Health: todo registro lleva `synthetic: true`.
struct PreviewData: TodayDataSource, SensorStatusSource {
    /// Instante "ahora" con el que se calcularon las lecturas.
    let now: Date
    let session: SensorSessionRecord
    let vectorSession: SensorSessionRecord
    /// Lecturas de ambas sesiones, ordenadas por hora de medición.
    let readings: [GlucoseReading]
    let events: [DiaryEvent]
    let status: SensorStatusSnapshot

    // MARK: Parámetros de la curva simulada

    static let sessionDays = 3
    static let warmupMinutes = 60
    static let wearMinutes = 14 * 24 * 60
    /// Minutos entre la última lectura y `now`.
    static let latestAgeMinutes = 2
    /// La desconexión empieza 125 min antes de la última lectura y dura 25 min.
    static let disconnectionStartMinutesBeforeLatest = 125
    static let disconnectionMinutes = 25
    /// Cuatro lecturas con bandera de calidad, 14 h antes de la última.
    static let qualityFlagStartMinutesBeforeLatest = 14 * 60
    static let qualityFlagCount = 4

    init(now: Date = .now, sensorState: SensorPresentationState = .streaming) {
        let nowEpoch = Int64(now.timeIntervalSince1970)
        let activation = nowEpoch - Int64(Self.sessionDays * 24 * 3_600)
        let session = Self.makeSession(
            id: "synthetic-preview-session",
            activation: activation,
            warmupMinutes: Self.warmupMinutes,
            wearMinutes: Self.wearMinutes,
            lastLifeCount: Self.sessionDays * 24 * 60 - Self.latestAgeMinutes
        )
        // La sesión de los vectores terminó una hora antes de que empezara la actual.
        let vectorActivation = activation - Int64(3_600 + 15_175 * 60)
        let vectorSession = Self.makeSession(
            id: "synthetic-juggluco-vectors",
            activation: vectorActivation,
            warmupMinutes: 0,
            wearMinutes: Self.wearMinutes,
            lastLifeCount: 15_175
        )
        self.now = now
        self.session = session
        self.vectorSession = vectorSession

        let curve = Self.simulatedReadings(session: session, activation: activation)
        let vectors = JugglucoVector.all.map { $0.reading(session: vectorSession) }
        self.readings = (curve + vectors).sorted { $0.measuredAt < $1.measuredAt }
        self.events = Self.simulatedEvents(activation: activation, now: nowEpoch)
        self.status = Self.makeStatus(state: sensorState, session: session, now: now)
    }

    // MARK: TodayDataSource

    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading] {
        readings.filter { range.contains($0.measuredAt) }
    }

    func latestEligibleReading() async throws -> GlucoseReading? {
        readings.filter { $0.eligibility.isEligible && $0.value != nil }.max { $0.measuredAt < $1.measuredAt }
    }

    func diaryEvents(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        events.filter { range.contains($0.at) }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    // MARK: SensorStatusSource

    func currentStatus() async -> SensorStatusSnapshot { status }

    func statusUpdates() -> AsyncStream<SensorStatusSnapshot> {
        AsyncStream { $0.finish() }
    }

    // MARK: Arranque de depuración

    /// Estado forzado por el argumento de lanzamiento `-previewSensorState <caso>` (solo DEBUG).
    static var launchSensorState: SensorPresentationState? {
        if case .preview(let state) = AppLaunchMode.resolve() { return state }
        return nil
    }
}

// MARK: - Construcción

private extension PreviewData {
    static let timeZone = "America/Bogota"

    static func makeSession(
        id: String,
        activation: Int64,
        warmupMinutes: Int,
        wearMinutes: Int,
        lastLifeCount: Int
    ) -> SensorSessionRecord {
        SensorSessionRecord(
            sessionID: id,
            sensorFamily: .lingo,
            productType: 9,
            securityVersion: 3,
            sensorSerialHash: String(repeating: "0", count: 64),
            synthetic: true,
            sensorSerialRedacted: "SYN",
            warmupMinutes: warmupMinutes,
            wearMinutes: wearMinutes,
            activationTimeEpochS: activation,
            activationTimeSource: .command,
            activatedByAppID: "lingoscan-preview",
            activationSource: .thisApp,
            activationState: .authenticated,
            receiverIDPresent: true,
            lastLifeCount: lastLifeCount
        )
    }

    static func makeStatus(state: SensorPresentationState, session: SensorSessionRecord, now: Date) -> SensorStatusSnapshot {
        var profile = SensorPresentationProfile(
            family: .lingo,
            productType: 9,
            securityVersion: 3,
            receiverIDPartial: "••••A3F2",
            synthetic: true
        )
        switch state {
        case .noSensor:
            return .noSensor
        case .paused:
            return SensorStatusSnapshot(state: .paused, profile: profile)
        case .identified, .incompatible, .readyToActivate, .activating, .pairing, .authenticationFailed:
            if state == .incompatible { profile.productType = 4; profile.family = .libre3 }
        case .warmingUp:
            profile.warmupEndsAt = now.addingTimeInterval(42 * 60)
            profile.sessionEndsAt = now.addingTimeInterval(Double(wearMinutes - 18) * 60)
            profile.lastConnection = now.addingTimeInterval(-60)
        case .streaming, .paired, .reconnecting, .stale, .ended:
            profile.warmupEndsAt = session.activatedAt.date.addingTimeInterval(Double(warmupMinutes) * 60)
            profile.sessionEndsAt = session.activatedAt.date.addingTimeInterval(Double(wearMinutes) * 60)
            profile.lastConnection = now.addingTimeInterval(-Double(latestAgeMinutes) * 60)
            if state == .stale { profile.lastConnection = now.addingTimeInterval(-9 * 60) }
            if state == .ended { profile.sessionEndsAt = now.addingTimeInterval(-3_600) }
        }
        return SensorStatusSnapshot(state: state, profile: profile)
    }

    /// Curva simulada: ritmo diurno, tres comidas al día y ruido determinista. Sin aleatoriedad real.
    static func simulatedReadings(session: SensorSessionRecord, activation: Int64) -> [GlucoseReading] {
        let totalMinutes = sessionDays * 24 * 60
        let latest = totalMinutes - latestAgeMinutes
        let disconnection = (latest - disconnectionStartMinutesBeforeLatest)
            ..< (latest - disconnectionStartMinutesBeforeLatest + disconnectionMinutes)
        let qualityFlagged = (latest - qualityFlagStartMinutesBeforeLatest)
            ..< (latest - qualityFlagStartMinutesBeforeLatest + qualityFlagCount)
        let meals = mealMinutes(activation: activation, totalMinutes: totalMinutes)

        var values: [Int] = []
        values.reserveCapacity(latest + 1)
        for minute in 0...latest {
            values.append(simulatedValue(minute: minute, activation: activation, meals: meals))
        }

        var result: [GlucoseReading] = []
        result.reserveCapacity(latest + 1)
        for lifeCount in 0...latest where !disconnection.contains(lifeCount) {
            let raw: RawReading
            if lifeCount < session.warmupMinutes {
                raw = RawReading(trend: 0, qualityFlag: true, channel: 1)
            } else if qualityFlagged.contains(lifeCount) {
                raw = RawReading(trend: 0, qualityFlag: true, channel: 1)
            } else {
                let value = values[lifeCount]
                let previous = values[max(0, lifeCount - 5)]
                raw = RawReading(
                    capped: value,
                    uncapped: value,
                    rateCenti: (value - previous) * 20,
                    trend: trend(forRatePerMinute: Double(value - previous) / 5),
                    actionable: false,
                    temperatureCenti: 3_200 + (lifeCount % 40),
                    rangeBits: 0x4000,
                    qualityFlag: false,
                    channel: 1
                )
            }
            result.append(reading(session: session, lifeCount: lifeCount, raw: raw))
        }
        return result
    }

    static func reading(session: SensorSessionRecord, lifeCount: Int, raw: RawReading) -> GlucoseReading {
        let measuredAt = MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: lifeCount)
        // Los datos sintéticos se evalúan como si fueran reales (como en un paquete sintético del contrato §6)
        // para que la gráfica los muestre; `synthetic: true` los mantiene fuera de Health.
        let eligibility = LingoScanV1Policy.evaluate(
            raw: raw,
            lifeCount: lifeCount,
            warmupMinutes: session.warmupMinutes,
            synthetic: true,
            deleted: false,
            inSyntheticPackage: true
        )
        return GlucoseReading(
            sessionID: session.sessionID,
            lifeCount: lifeCount,
            measuredAt: measuredAt,
            receivedAt: measuredAt.adding(seconds: 1),
            tzAtCapture: timeZone,
            origin: .live,
            value: LingoScanV1Policy.value(for: raw, eligibility: eligibility),
            raw: raw,
            eligibility: eligibility,
            synthetic: true
        )
    }

    /// Escala de Juggluco: 1 bajando rápido … 5 subiendo rápido (mg/dL por minuto).
    static func trend(forRatePerMinute rate: Double) -> Int {
        switch rate {
        case ..<(-2): 1
        case ..<(-1): 2
        case ...1: 3
        case ...2: 4
        default: 5
        }
    }

    /// Minutos (desde la activación) de las comidas: 07:30, 12:45 y 19:15 hora local de cada día.
    static func mealMinutes(activation: Int64, totalMinutes: Int) -> [Int] {
        mealDates(activation: activation, until: activation + Int64(totalMinutes * 60)).map {
            Int(($0.timeIntervalSince1970 - Double(activation)) / 60)
        }
    }

    static func mealDates(activation: Int64, until end: Int64) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let first = Date(timeIntervalSince1970: TimeInterval(activation))
        let lastDate = Date(timeIntervalSince1970: TimeInterval(end))
        var dates: [Date] = []
        var day = calendar.startOfDay(for: first)
        while day <= lastDate {
            for (hour, minute) in [(7, 30), (12, 45), (19, 15)] {
                if let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                   date >= first, date <= lastDate {
                    dates.append(date)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    static func simulatedValue(minute: Int, activation: Int64, meals: [Int]) -> Int {
        let hours = Double(minute) / 60
        let circadian = 108 + 8 * sin(hours / 24 * 2 * .pi + 0.6)
        var excursion = 0.0
        for meal in meals where minute > meal {
            let x = Double(minute - meal) / 50
            excursion += 62 * x * exp(1 - x)
        }
        let noise = 3.0 * sin(Double(minute) * 0.7) + 2.0 * sin(Double(minute) * 0.23 + 1)
        return min(max(Int((circadian + excursion + noise).rounded()), 55), 240)
    }

    static func simulatedEvents(activation: Int64, now: Int64) -> [DiaryEvent] {
        var events: [DiaryEvent] = []
        for (index, date) in mealDates(activation: activation, until: now).enumerated() {
            events.append(event(id: "synthetic-meal-\(index)", kind: .meal, at: date, durationMin: nil, carbs: 45 + Double(index % 3) * 10))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let first = Date(timeIntervalSince1970: TimeInterval(activation))
        var day = calendar.startOfDay(for: first)
        var index = 0
        while day.timeIntervalSince1970 <= Double(now) {
            if let date = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day),
               date >= first, date.timeIntervalSince1970 <= Double(now), index % 2 == 0 {
                events.append(event(id: "synthetic-exercise-\(index)", kind: .exercise, at: date, durationMin: 45, carbs: nil))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            index += 1
        }
        return events
    }

    static func event(id: String, kind: DiaryEventKind, at date: Date, durationMin: Int?, carbs: Double?) -> DiaryEvent {
        let instant = UTCInstant(date)
        return DiaryEvent(
            eventID: id,
            kind: kind,
            at: instant,
            tz: timeZone,
            durationMin: durationMin,
            carbsG: carbs,
            createdAt: instant,
            updatedAt: instant,
            editID: "\(id)-edit-1",
            editedByAppID: "lingoscan-preview",
            synthetic: true
        )
    }
}

// MARK: - Vectores públicos de Juggluco

/// Una trama pública de Juggluco (`docs/PROTOCOLO_LINGO.md` §8) ya decodificada.
/// Sin claves ni datos reales de una persona: son los plaintexts del autor de Juggluco.
extension PreviewData {
    struct JugglucoVector: Sendable {
        let name: String
        let lifeCount: Int
        let capped: Int?
        let uncapped: Int?
        let historicLifeCount: Int?
        let historicCapped: Int?
        /// `nil` cuando el rate es -32768 (desconocido).
        let rateCenti: Int?
        let trend: Int
        let temperatureCenti: Int?
        /// `true` cuando la glucosa no es válida (bit 15 de la palabra de glucosa).
        let qualityFlag: Bool

        func reading(session: SensorSessionRecord) -> GlucoseReading {
            let raw = RawReading(
                capped: capped,
                uncapped: uncapped,
                historicCapped: historicCapped,
                historicUncapped: historicCapped,
                historicLifeCount: historicLifeCount,
                rateCenti: rateCenti,
                trend: trend,
                actionable: false,
                temperatureCenti: temperatureCenti,
                rangeBits: capped == nil ? nil : 0x4000,
                qualityFlag: qualityFlag,
                channel: 1
            )
            // Los vectores se evalúan con `warmupMinutes = 0` en su sesión: el calentamiento lo marca el bit 15 (T-07, decisión 8).
            return PreviewData.reading(session: session, lifeCount: lifeCount, raw: raw)
        }

        private static func warmup(_ name: String, _ lifeCount: Int) -> JugglucoVector {
            JugglucoVector(
                name: name, lifeCount: lifeCount, capped: nil, uncapped: nil, historicLifeCount: 0,
                historicCapped: nil, rateCenti: nil, trend: 0, temperatureCenti: nil, qualityFlag: true
            )
        }

        /// Tramas de §8.1 (4 de calentamiento), §8.2 (2 con glucosa 201 mg/dL) y §8.3 (5 con rate/trend distintos;
        /// la sexta de §8.3 repite el vector de lc 58 y colapsaría en el mismo `recordID`).
        static let all: [JugglucoVector] = [
            warmup("prior#1", 1),
            warmup("prior#2", 2),
            warmup("live#1", 3),
            warmup("live#2", 4),
            JugglucoVector(
                name: "warm lc58", lifeCount: 58, capped: 201, uncapped: 201, historicLifeCount: 40,
                historicCapped: nil, rateCenti: nil, trend: 0, temperatureCenti: 3_283, qualityFlag: false
            ),
            JugglucoVector(
                name: "warm lc63", lifeCount: 63, capped: 201, uncapped: 208, historicLifeCount: 45,
                historicCapped: nil, rateCenti: nil, trend: 0, temperatureCenti: 3_257, qualityFlag: false
            ),
            JugglucoVector(
                name: "trend lc14345", lifeCount: 14_345, capped: 157, uncapped: 157, historicLifeCount: 14_325,
                historicCapped: 156, rateCenti: -19, trend: 3, temperatureCenti: nil, qualityFlag: false
            ),
            JugglucoVector(
                name: "trend lc14404", lifeCount: 14_404, capped: 137, uncapped: 137, historicLifeCount: 14_385,
                historicCapped: 172, rateCenti: -114, trend: 2, temperatureCenti: 3_087, qualityFlag: false
            ),
            JugglucoVector(
                name: "trend lc14409", lifeCount: 14_409, capped: 120, uncapped: 120, historicLifeCount: 14_390,
                historicCapped: 163, rateCenti: -204, trend: 1, temperatureCenti: 3_088, qualityFlag: false
            ),
            JugglucoVector(
                name: "trend lc15035", lifeCount: 15_035, capped: 158, uncapped: 158, historicLifeCount: 15_015,
                historicCapped: 99, rateCenti: 256, trend: 5, temperatureCenti: 2_820, qualityFlag: false
            ),
            JugglucoVector(
                name: "trend lc15175", lifeCount: 15_175, capped: 155, uncapped: 155, historicLifeCount: 15_155,
                historicCapped: 195, rateCenti: nil, trend: 3, temperatureCenti: 3_122, qualityFlag: false
            ),
        ]
    }
}

// MARK: - Historial sintético para Reportes (T-27c)

/// Once días sintéticos de un sensor anterior (también `synthetic: true`), para que Reportes tenga 14 días con comidas,
/// ejercicio, noches con alguna bajada y un hueco largo. Solo lo usa `PreviewReportsDataSource`; Hoy no lo ve.
extension PreviewData {
    static let reportHistoryDays = 11
    /// Hueco de 3 h en el día 7 del historial (huecos del resumen).
    static let reportHistoryGapDay = 7

    /// Lecturas y eventos del historial: terminan una hora antes de que empiece la sesión actual.
    func reportHistory() -> (readings: [GlucoseReading], events: [DiaryEvent]) {
        let days = Self.reportHistoryDays
        let totalMinutes = days * 24 * 60
        let activation = session.activationTimeEpochS - 3_600 - Int64(totalMinutes * 60)
        let history = Self.makeSession(
            id: "synthetic-report-history",
            activation: activation,
            warmupMinutes: Self.warmupMinutes,
            wearMinutes: Self.wearMinutes,
            lastLifeCount: totalMinutes - 1
        )
        let events = Self.historyEvents(activation: activation, end: activation + Int64(totalMinutes * 60))
        let minuteOf: (DiaryEvent) -> Int = { Int(($0.at.epochSeconds - activation) / 60) }
        let meals = events.filter { $0.kind == .meal }.map { (minute: minuteOf($0), carbs: $0.carbsG ?? 0) }
        let exercise = events.filter { $0.kind == .exercise }.map { (minute: minuteOf($0), duration: $0.durationMin ?? 30) }
        let lows = Self.historyLowMinutes(activation: activation, days: days)
        let gapStart = Self.reportHistoryGapDay * 1_440 + 10 * 60
        let gap = gapStart..<(gapStart + 180)

        var readings: [GlucoseReading] = []
        readings.reserveCapacity(totalMinutes)
        var previous = 100
        for minute in 0..<totalMinutes where !gap.contains(minute) {
            let raw: RawReading
            if minute < Self.warmupMinutes {
                raw = RawReading(trend: 0, qualityFlag: true, channel: 1)
            } else {
                let value = Self.historyValue(minute: minute, meals: meals, exercise: exercise, lows: lows)
                raw = RawReading(
                    capped: value, uncapped: value, rateCenti: (value - previous) * 100,
                    trend: Self.trend(forRatePerMinute: Double(value - previous)), actionable: false,
                    temperatureCenti: 3_200, rangeBits: 0x4000, qualityFlag: false, channel: 1)
                previous = value
            }
            readings.append(Self.reading(session: history, lifeCount: minute, raw: raw))
        }
        return (readings, events)
    }
}

private extension PreviewData {
    /// Glucosa simulada del historial: ritmo diurno, deriva por día, comidas proporcionales a los carbohidratos,
    /// bajada durante y después del ejercicio y alguna bajada nocturna. Determinista.
    static func historyValue(
        minute: Int,
        meals: [(minute: Int, carbs: Double)],
        exercise: [(minute: Int, duration: Int)],
        lows: [Int]
    ) -> Int {
        let hours = Double(minute) / 60
        let day = Double(minute / 1_440)
        var value = 104 + 8 * sin(hours / 24 * 2 * .pi + 0.6) + 7 * sin(day * 1.7)
        for meal in meals where minute > meal.minute && minute < meal.minute + 300 {
            let x = Double(minute - meal.minute) / 48
            value += (18 + meal.carbs * 0.95) * x * exp(1 - x)
        }
        for session in exercise where minute >= session.minute && minute < session.minute + session.duration + 150 {
            let elapsed = Double(minute - session.minute)
            let duration = Double(session.duration)
            let depth = 14 + duration * 0.3
            value -= elapsed <= duration ? depth * elapsed / duration : depth * exp(-(elapsed - duration) / 55)
        }
        for low in lows {
            let d = Double(minute - low) / 35
            value -= 46 * exp(-d * d)
        }
        value += 3 * sin(Double(minute) * 0.7) + 2 * sin(Double(minute) * 0.23 + 1)
        return min(max(Int(value.rounded()), 48), 280)
    }

    /// Bajadas nocturnas (≈ 03:10 local) en los días 2 y 8 del historial.
    static func historyLowMinutes(activation: Int64, days: Int) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let first = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(activation)))
        return [2, 8].filter { $0 < days }.compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset + 1, to: first),
                  let date = calendar.date(bySettingHour: 3, minute: 10, second: 0, of: day) else { return nil }
            return Int((date.timeIntervalSince1970 - Double(activation)) / 60)
        }
    }

    /// Comidas a hora variable con carbohidratos distintos, merienda algunos días y ejercicio en días alternos.
    static func historyEvents(activation: Int64, end: Int64) -> [DiaryEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let first = Date(timeIntervalSince1970: TimeInterval(activation + Int64(warmupMinutes * 60)))
        let last = Date(timeIntervalSince1970: TimeInterval(end))
        let plan: [(hour: Int, minute: Int, carbs: [Double])] = [
            (7, 20, [35, 50, 28, 62]), (12, 50, [70, 55, 85, 40]), (16, 10, [15, 0, 22, 0]), (19, 30, [48, 90, 38, 65]),
        ]
        let workouts: [(hour: Int, minute: Int, duration: Int)] = [(17, 30, 45), (6, 40, 30), (18, 0, 75), (17, 45, 20)]
        var events: [DiaryEvent] = []
        var day = calendar.startOfDay(for: first)
        var index = 0
        while day <= last {
            for (slot, meal) in plan.enumerated() {
                let carbs = meal.carbs[(index + slot) % meal.carbs.count]
                guard carbs > 0,
                      let base = calendar.date(bySettingHour: meal.hour, minute: meal.minute, second: 0, of: day) else { continue }
                let date = base.addingTimeInterval(Double((index * 7) % 25) * 60)
                guard date >= first, date <= last else { continue }
                events.append(event(id: "synthetic-history-meal-\(index)-\(slot)", kind: .meal, at: date, durationMin: nil, carbs: carbs))
            }
            let workout = workouts[(index / 2) % workouts.count]
            if index % 2 == 1,
               let date = calendar.date(bySettingHour: workout.hour, minute: workout.minute, second: 0, of: day),
               date >= first, date <= last {
                events.append(event(id: "synthetic-history-exercise-\(index)", kind: .exercise, at: date,
                                    durationMin: workout.duration, carbs: nil))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            index += 1
        }
        return events
    }
}
