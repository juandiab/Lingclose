import Foundation
import LingoCore
import Observation

/// Estado de Hoy: último valor elegible, curva del período, huecos, marcas y estado del sensor.
/// Sin lógica de protocolo; todo llega por `TodayDataSource` y `SensorStatusSource`.
@MainActor
@Observable
final class TodayViewModel {
    enum LoadFailure: Error, Equatable {
        case readingsUnavailable
    }

    /// Período de la curva. Al cambiarlo, la vista vuelve a llamar a `refresh()` con `.task(id:)`.
    var period: TodayPeriod = .sixHours

    /// Días respecto de hoy: 0 es hoy (ventana móvil de `period`), -1 ayer… Un día anterior muestra el día completo.
    private(set) var dayOffset = 0

    /// Líneas de referencia (mg/dL). El umbral alto es también el de los picos sombreados.
    var referenceLow = ReferenceLines.defaultLow
    var referenceHigh = ReferenceLines.defaultHigh {
        didSet { if referenceHigh != oldValue { recomputeSpikes() } }
    }

    private(set) var latest: GlucoseReading?
    private(set) var segments: [GlucoseSegment] = []
    private(set) var points: [GlucosePoint] = []
    private(set) var spikes: [TodaySpike] = []
    /// Eventos del día mostrado (comidas, ejercicio y notas), para la fila "Registro".
    private(set) var dayEntryCount = 0
    private(set) var gaps: [GlucoseGap] = []
    private(set) var marks: [DiaryMark] = []
    /// Tiempo en rango, media y SD del período visible (informativo, no médico).
    private(set) var stats = BasicStats(samples: [])
    private(set) var sensor: SensorStatusSnapshot = .noSensor
    private(set) var failure: LoadFailure?
    /// `true` tras la primera carga, para no mostrar el estado vacío antes de tiempo.
    private(set) var hasLoaded = false
    /// Instante con el que se calculó la ventana visible.
    private(set) var windowEnd: Date
    private(set) var windowStart: Date

    private let dataSource: any TodayDataSource
    private let sensorSource: any SensorStatusSource
    private let clock: @Sendable () -> Date
    @ObservationIgnored let calendar: Calendar
    /// Diario en memoria cuando la fuente no trae uno propio (previsualización): el registro rápido se ve en la curva.
    @ObservationIgnored private let fallbackStore = InMemoryDiaryStore()

    /// Sin lectura en más de 5 minutos el dato se considera atrasado (`ARQUITECTURA.md` §3).
    static let staleAfter: TimeInterval = 300

    init(
        dataSource: any TodayDataSource,
        sensorSource: any SensorStatusSource,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.dataSource = dataSource
        self.sensorSource = sensorSource
        self.clock = clock
        self.calendar = calendar
        let now = clock()
        self.windowEnd = now
        self.windowStart = now.addingTimeInterval(-TodayPeriod.sixHours.duration)
    }

    /// Dónde escribe el registro rápido y qué lista el Diario del día.
    var diaryStore: any DiaryStore { dataSource.diaryStore ?? fallbackStore }

    var now: Date { clock() }

    // MARK: Derivados

    var isToday: Bool { dayOffset == 0 }

    var canGoForward: Bool { dayOffset < 0 }

    /// Clave de la ventana visible: cambia con el período o el día y dispara la recarga.
    struct WindowKey: Hashable { let period: TodayPeriod; let dayOffset: Int }

    var windowKey: WindowKey { WindowKey(period: period, dayOffset: dayOffset) }

    /// Primer instante del día mostrado.
    var shownDay: Date {
        let today = calendar.startOfDay(for: clock())
        return calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
    }

    func goBack() { dayOffset -= 1 }

    func goForward() { if canGoForward { dayOffset += 1 } }

    func goToToday() { dayOffset = 0 }

    /// Salta a un día del selector de fecha; los días futuros se acotan a hoy.
    func select(day: Date) {
        let today = calendar.startOfDay(for: clock())
        let target = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        dayOffset = min(days, 0)
    }

    /// Ventana de la curva: móvil de `period` para hoy; el día completo para los demás.
    func window(now: Date) -> (start: Date, end: Date) {
        guard dayOffset != 0 else { return (now.addingTimeInterval(-period.duration), now) }
        let start = shownDay
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }

    var latestValue: Int? { latest?.value }

    var trend: TrendDirection? { TrendDirection(rawTrend: latest?.raw.trend) }

    /// Sin ninguna lectura que mostrar (ni última elegible ni puntos en el período).
    var hasNoData: Bool { hasLoaded && failure == nil && latest == nil && segments.isEmpty }

    var isSynthetic: Bool { latest?.synthetic ?? sensor.profile?.synthetic ?? false }

    /// Minutos enteros desde la última lectura elegible; `nil` si no hay lectura.
    func ageMinutes(at now: Date) -> Int? {
        guard let latest else { return nil }
        return max(0, Int(now.timeIntervalSince(latest.measuredAt.date) / 60))
    }

    func isStale(at now: Date) -> Bool {
        guard let latest else { return false }
        return now.timeIntervalSince(latest.measuredAt.date) > Self.staleAfter
    }

    /// Valor, tendencia, antigüedad y estado del sensor en una sola frase para VoiceOver.
    func spokenSummary(at now: Date) -> String {
        guard let value = latestValue, let minutes = ageMinutes(at: now) else {
            return String(localized: "today.a11y.noValue", defaultValue: "Sin lectura válida todavía")
        }
        let age = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        let trendText = trend?.title ?? TrendDirection.unknownTitle
        return String(
            localized: "today.a11y.value",
            defaultValue: "\(value) miligramos por decilitro, \(trendText), hace \(age), \(sensor.state.spokenPhrase)"
        )
    }

    /// Rango vertical de la curva: incluye las líneas de referencia y deja bajo la línea baja el espacio
    /// de los índices de pico y los marcadores.
    var chartValueDomain: ClosedRange<Int> {
        let values = points.map(\.value)
        let low = min(values.min() ?? referenceLow, referenceLow)
        let high = max(values.max() ?? referenceHigh, referenceHigh, 220)
        return max(0, (low - 75) / 10 * 10)...((high + 10 + 9) / 10 * 10)
    }

    /// Tolerancia de la lectura al arrastrar: con una lectura por minuto, el punto más lejano de una
    /// racha continua está a 30 s; más allá de 45 s el dedo está sobre un hueco.
    static let selectionTolerance: TimeInterval = 45

    /// Lectura elegible más cercana en tiempo a `date`; `nil` si cae en un hueco o fuera de los datos.
    func nearestPoint(to date: Date) -> GlucosePoint? {
        guard !points.isEmpty else { return nil }
        // `points` está ordenado por fecha: búsqueda binaria del primer punto no anterior a `date`.
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < date { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter { points.indices.contains($0) }.map { points[$0] }
        let best = candidates.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        guard let best, abs(best.date.timeIntervalSince(date)) <= Self.selectionTolerance else { return nil }
        return best
    }

    /// "142 mg/dL a las 12:02" o "Sin lectura a las 12:02" para el instante señalado.
    func readoutText(at date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if let point = nearestPoint(to: date) {
            return String(localized: "today.readout.value", defaultValue: "\(point.value) mg/dL a las \(point.date.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "today.readout.none", defaultValue: "Sin lectura a las \(time)")
    }

    // MARK: Carga

    /// Carga el estado del sensor y sigue los avisos de datos nuevos y los cambios de estado hasta que se cancela la tarea.
    /// La primera carga de la curva la dispara la vista con `.task(id: period)`.
    func observe() async {
        await refreshSensor()
        async let changes: Void = followChanges()
        async let statuses: Void = followSensor()
        _ = await (changes, statuses)
    }

    private func followChanges() async {
        for await _ in dataSource.changes() {
            await refresh()
        }
    }

    private func followSensor() async {
        for await snapshot in sensorSource.statusUpdates() {
            sensor = snapshot
        }
    }

    func refreshSensor() async {
        sensor = await sensorSource.currentStatus()
    }

    /// Recalcula la ventana, la última lectura, las marcas y los picos.
    func refresh() async {
        let end = clock()
        let (start, windowEndDate) = window(now: end)
        windowStart = start
        windowEnd = windowEndDate
        defer { hasLoaded = true }
        let range = UTCInstant(start)...UTCInstant(windowEndDate)
        let day = shownDay
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let dayRange = UTCInstant(day)...UTCInstant(nextDay.addingTimeInterval(-1))
        do {
            async let latestReading = dataSource.latestEligibleReading()
            async let readings = dataSource.readings(in: range)
            async let windowEvents = mergedEvents(in: range)
            async let dayEvents = mergedEvents(in: dayRange)
            let (newLatest, newReadings, newEvents, newDayEvents) = try await (latestReading, readings, windowEvents, dayEvents)
            latest = newLatest
            let newSegments = GlucoseSegmenter.segments(from: newReadings.compactMap(GlucosePoint.init))
            segments = newSegments
            points = newSegments.flatMap(\.points)
            gaps = GlucoseSegmenter.gaps(in: newSegments)
            stats = BasicStats(
                samples: points.map {
                    BasicStats.Sample(measuredAt: UTCInstant($0.date), valueMgdl: $0.value)
                },
                range: Tokens.ReferenceRange.bounds,
                window: range)
            marks = newEvents.compactMap(DiaryMark.init).sorted { $0.date < $1.date }
            dayEntryCount = newDayEvents.filter { !$0.deleted }.count
            recomputeSpikes()
            failure = nil
        } catch {
            failure = .readingsUnavailable
        }
    }

    /// Eventos de la fuente más los del diario en memoria de respaldo (sin duplicar por `eventID`).
    private func mergedEvents(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent] {
        var result = try await dataSource.diaryEvents(in: range)
        if dataSource.diaryStore == nil {
            let local = try await fallbackStore.events(in: range)
            let known = Set(result.map(\.eventID))
            result += local.filter { !known.contains($0.eventID) }
        }
        return result
    }

    private func recomputeSpikes() {
        let samples = points.map { BasicStats.Sample(measuredAt: UTCInstant($0.date), valueMgdl: $0.value) }
        spikes = SpikeIndex.spikes(in: samples, threshold: referenceHigh).map(TodaySpike.init)
    }
}
