import Foundation
import LingoCore
import Observation

/// Estado de Hoy: último valor elegible, curva desplazable con zoom, huecos, marcas y estado del sensor.
/// Sin lógica de protocolo; todo llega por `TodayDataSource` y `SensorStatusSource`.
///
/// Ventanas:
/// - **visible**: `scrollPosition…scrollPosition + visibleLength` (lo que se ve; la gráfica la mueve en vivo).
/// - **asentada**: `windowStart…windowEnd`, la visible ~250 ms después del último movimiento; sobre ella se
///   calculan estadísticas, picos y el descriptor de accesibilidad.
/// - **cargada**: `loadedStart…loadedEnd`, la visible ampliada una `visibleLength` por cada lado (acotada a
///   ahora). Es el dominio X de la gráfica; se recarga cuando el centro visible sale del tercio central.
@MainActor
@Observable
final class TodayViewModel {
    enum LoadFailure: Error, Equatable {
        case readingsUnavailable
    }

    // MARK: Constantes

    static let minVisibleLength: TimeInterval = 3_600
    static let maxVisibleLength: TimeInterval = 86_400
    static let defaultVisibleLength = TodayPeriod.sixHours.duration
    /// Clave de `AppStorage` con la longitud visible libre (segundos), restaurada al abrir.
    static let visibleSecondsKey = "today.visibleSeconds"
    /// Clave de `AppStorage`: sombrear en la curva los episodios de subida o bajada rápida (por defecto sí).
    static let showRateEpisodesKey = "today.showRateEpisodes"
    /// La ventana está "en vivo" si termina a menos de este margen de ahora.
    static let liveTolerance: TimeInterval = 60
    /// Espera tras el último movimiento antes de recalcular o recargar.
    static let settleDelay: Duration = .milliseconds(250)
    /// Cambio relativo de la longitud visible que obliga a recargar.
    static let reloadLengthChange = 0.25
    /// Sin lectura en más de 5 minutos el dato se considera atrasado (`ARQUITECTURA.md` §3).
    static let staleAfter: TimeInterval = 300
    /// Tolerancia de la lectura del cursor: con una lectura por minuto, el punto más lejano de una
    /// racha continua está a 30 s; más allá de 45 s el dedo está sobre un hueco.
    static let selectionTolerance: TimeInterval = 45

    // MARK: Ventana visible

    /// Longitud visible, entre 1 h y 24 h. La fijan los chips, el pellizco y las acciones de accesibilidad.
    private(set) var visibleLength = TodayViewModel.defaultVisibleLength

    /// Borde izquierdo de la ventana visible. La gráfica lo escribe en vivo al desplazarse.
    var scrollPosition: Date {
        didSet { if scrollPosition != oldValue { scrollDidChange() } }
    }

    /// `true` si la ventana visible termina a menos de `liveTolerance` de ahora: sigue cada lectura nueva.
    private(set) var isLive = true

    /// Primer instante del día del fin de la ventana visible (título del navegador de días).
    private(set) var shownDay: Date

    /// Dominio X de la gráfica (rango cargado).
    private(set) var loadedStart: Date
    /// Cambia cuando una carga mueve el inicio del dominio: la gráfica se recrea en la posición de `scrollPosition`.
    private(set) var chartIdentity = 0
    private(set) var loadedEnd: Date

    /// Ventana visible asentada (tras el debounce).
    private(set) var windowStart: Date
    private(set) var windowEnd: Date

    /// Líneas de referencia (mg/dL). El umbral alto es también el de los picos sombreados.
    var referenceLow = ReferenceLines.defaultLow {
        didSet { if referenceLow != oldValue { recomputeVisible() } }
    }
    var referenceHigh = ReferenceLines.defaultHigh {
        didSet {
            guard referenceHigh != oldValue else { return }
            mealResponseCache.removeAll()
            recomputeVisible()
        }
    }

    // MARK: Datos

    private(set) var latest: GlucoseReading?
    /// Tramos crudos del rango cargado.
    private(set) var segments: [GlucoseSegment] = []
    /// Tramos reducidos para dibujar (≤ `GlucoseDownsampler.maxPoints`).
    private(set) var drawSegments: [GlucoseSegment] = []
    /// Puntos crudos del rango cargado, ordenados (cursor y dominio vertical).
    private(set) var points: [GlucosePoint] = []
    /// Puntos crudos de la ventana asentada (estadísticas, picos, VoiceOver).
    private(set) var visiblePoints: [GlucosePoint] = []
    private(set) var spikes: [TodaySpike] = []
    /// Episodios de subida o bajada rápida del rango cargado (T-23, informativos). La gráfica los sombrea.
    private(set) var rateEvents: [RateEvent] = []
    /// Eventos del día de `entriesDay` (comidas, ejercicio y notas), para la fila "Registro".
    private(set) var dayEntryCount = 0
    /// Día al que corresponde `dayEntryCount`.
    private(set) var entriesDay: Date
    private(set) var gaps: [GlucoseGap] = []
    private(set) var marks: [DiaryMark] = []
    /// Tiempo en rango, media y SD de la ventana visible (informativo, no médico).
    private(set) var stats = BasicStats(samples: [])
    private(set) var sensor: SensorStatusSnapshot = .noSensor
    private(set) var failure: LoadFailure?
    /// `true` tras la primera carga, para no mostrar el estado vacío antes de tiempo.
    private(set) var hasLoaded = false

    // MARK: Dependencias y estado interno

    private let dataSource: any TodayDataSource
    private let sensorSource: any SensorStatusSource
    private let clock: @Sendable () -> Date
    @ObservationIgnored let calendar: Calendar
    /// Diario en memoria cuando la fuente no trae uno propio (previsualización): el registro rápido se ve en la curva.
    @ObservationIgnored private let fallbackStore = InMemoryDiaryStore()
    /// Ventana visible y longitud con las que se hizo la última carga (su tercio central).
    @ObservationIgnored private var loadAnchor: (start: Date, end: Date, length: TimeInterval)?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// Respuestas a comida y efectos de ejercicio ya calculados por id de marca; se vacían en cada carga
    /// (y al cambiar la referencia alta, que entra en `timeAboveHigh`).
    @ObservationIgnored private var mealResponseCache: [DiaryMark.ID: MealResponse?] = [:]
    @ObservationIgnored private var exerciseEffectCache: [DiaryMark.ID: ExerciseEffect?] = [:]
    @ObservationIgnored private var loadGeneration = 0

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
        let start = now.addingTimeInterval(-Self.defaultVisibleLength)
        scrollPosition = start
        windowStart = start
        windowEnd = now
        loadedStart = start.addingTimeInterval(-Self.defaultVisibleLength)
        loadedEnd = now
        shownDay = calendar.startOfDay(for: now)
        entriesDay = calendar.startOfDay(for: now)
    }

    /// Dónde escribe el registro rápido y qué lista el Diario del día.
    var diaryStore: any DiaryStore { dataSource.diaryStore ?? fallbackStore }

    var now: Date { clock() }

    // MARK: Derivados

    var visibleStart: Date { scrollPosition }

    var visibleEnd: Date { scrollPosition.addingTimeInterval(visibleLength) }

    /// Chip que coincide con la longitud visible, o `nil` con un zoom libre.
    var period: TodayPeriod? { TodayPeriod.matching(visibleLength) }

    var isToday: Bool { shownDay == calendar.startOfDay(for: clock()) }

    var canGoForward: Bool { !isToday }

    var latestValue: Int? { latest?.value }

    var trend: TrendDirection? { TrendDirection(rawTrend: latest?.raw.trend) }

    /// Sin ninguna lectura que mostrar (ni última elegible ni puntos cargados).
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

    /// Rango vertical de la curva, adaptado a la ventana asentada (sigue al zoom y al desplazamiento ~250 ms
    /// después del último movimiento). Ver `valueDomain(values:low:high:hasMarks:)`.
    var chartValueDomain: ClosedRange<Int> {
        let window = windowStart...windowEnd
        return Self.valueDomain(
            values: visiblePoints.map(\.value),
            low: referenceLow,
            high: referenceHigh,
            hasMarks: marks.contains { window.contains($0.date) }
        )
    }

    /// Alto mínimo del dominio vertical: una noche plana no se amplía hasta parecer una montaña rusa.
    static let minimumDomainSpan = 90
    /// Margen extra bajo la curva para los marcadores de comida y ejercicio, solo si hay alguno visible.
    static let markerRoom = 25
    /// Límite inferior absoluto del dominio.
    static let domainFloor = 40

    /// Dominio vertical: de `min(mínimo, referencia baja) − 20` (decena inferior; − 25 más con marcas; nunca
    /// < 40) a `max(máximo, referencia alta) + 15` (decena superior), con un alto mínimo de 90 mg/dL repartido
    /// arriba y abajo. Sin valores, se usan solo las referencias.
    static func valueDomain(values: [Int], low: Int, high: Int, hasMarks: Bool) -> ClosedRange<Int> {
        func floorToTen(_ value: Int) -> Int { Int((Double(value) / 10).rounded(.down)) * 10 }
        func ceilToTen(_ value: Int) -> Int { Int((Double(value) / 10).rounded(.up)) * 10 }

        var lower = min(values.min() ?? low, low) - 20
        if hasMarks { lower -= markerRoom }
        lower = max(domainFloor, floorToTen(lower))
        var upper = ceilToTen(max(values.max() ?? high, high) + 15)

        let deficit = minimumDomainSpan - (upper - lower)
        if deficit > 0 {
            let below = min(floorToTen(deficit / 2), lower - domainFloor)
            lower -= below
            upper = ceilToTen(lower + minimumDomainSpan)
        }
        return lower...upper
    }

    /// Lectura elegible más cercana en tiempo a `date`; `nil` si cae en un hueco o fuera de los datos.
    func nearestPoint(to date: Date) -> GlucosePoint? {
        guard !points.isEmpty else { return nil }
        let low = Self.firstIndex(in: points, notBefore: date)
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

    // MARK: Insights (T-23)

    /// Respuesta de la glucosa a una comida con las lecturas cargadas; `nil` si no es comida o no hay datos
    /// suficientes (comida de hace menos de 1 h, hueco > 20 min en la primera hora). Ver `MealResponse`.
    /// Limitación: solo usa el rango cargado; una comida a menos de 3 h de su borde derecho (que no sea
    /// ahora) se evalúa con menos datos.
    func mealResponse(for mark: DiaryMark) -> MealResponse? {
        guard mark.kind == .meal else { return nil }
        if let cached = mealResponseCache[mark.id] { return cached }
        let start = mark.date.addingTimeInterval(-Double(MealResponse.baselineWindow) * 2)
        let end = mark.date.addingTimeInterval(Double(MealResponse.horizon))
        let response = MealResponse(mealAt: UTCInstant(mark.date), samples: samples(from: start, to: end), highReference: referenceHigh)
        mealResponseCache[mark.id] = .some(response)
        return response
    }

    /// Efecto de un ejercicio (fin = duración de la marca o 30 min) con las lecturas cargadas. Ver `ExerciseEffect`.
    func exerciseEffect(for mark: DiaryMark) -> ExerciseEffect? {
        guard mark.kind == .exercise else { return nil }
        if let cached = exerciseEffectCache[mark.id] { return cached }
        let end = mark.endDate ?? mark.date.addingTimeInterval(Double(ExerciseEffect.defaultDuration))
        let from = mark.date.addingTimeInterval(-Double(ExerciseEffect.beforeWindow))
        let to = end.addingTimeInterval(Double(ExerciseEffect.afterWindow))
        let effect = ExerciseEffect(start: UTCInstant(mark.date), end: UTCInstant(end), samples: samples(from: from, to: to))
        exerciseEffectCache[mark.id] = .some(effect)
        return effect
    }

    /// Episodios rápidos que se solapan con la ventana asentada.
    var visibleRateEvents: [RateEvent] {
        let start = UTCInstant(windowStart), end = UTCInstant(windowEnd)
        return rateEvents.filter { $0.end >= start && $0.start <= end }
    }

    /// Resumen de la ventana asentada para la fila "Insights": subidas y bajadas rápidas y la mejor y la peor
    /// respuesta a comida. `nil` si no hay nada que mostrar.
    var insights: TodayInsights? {
        let window = windowStart...windowEnd
        let meals = marks
            .filter { $0.kind == .meal && window.contains($0.date) }
            .compactMap { mark in mealResponse(for: mark).map { TodayMealInsight(mark: mark, response: $0) } }
        let insights = TodayInsights(rateEvents: visibleRateEvents, meals: meals)
        return insights.isEmpty ? nil : insights
    }

    /// Lecturas crudas cargadas en `[start, end]` como muestras de `LingoCore`.
    private func samples(from start: Date, to end: Date) -> [BasicStats.Sample] {
        let lower = Self.firstIndex(in: points, notBefore: start)
        let upper = Self.firstIndex(in: points, after: end)
        guard lower < upper else { return [] }
        return points[lower..<upper].map(Self.sample)
    }

    private static func sample(_ point: GlucosePoint) -> BasicStats.Sample {
        BasicStats.Sample(measuredAt: UTCInstant(point.date), valueMgdl: point.value)
    }

    // MARK: Zoom

    /// Acota una longitud a 1 h…24 h.
    static func clampedLength(_ length: TimeInterval) -> TimeInterval {
        min(max(length, minVisibleLength), maxVisibleLength)
    }

    /// `true` si al pasar de `old` a `new` se alcanza o cruza exactamente uno de los chips (para el haptic).
    static func crossesPeriod(from old: TimeInterval, to new: TimeInterval) -> Bool {
        guard old != new else { return false }
        let range = min(old, new)...max(old, new)
        let crossed = TodayPeriod.allCases.filter { range.contains($0.duration) && $0.duration != old }
        return crossed.count == 1
    }

    /// Fija la longitud visible conservando el fin de la ventana (chips, VoiceOver, restauración).
    func setVisibleLength(_ length: TimeInterval) {
        let newLength = Self.clampedLength(length)
        let end = isLive ? clock() : visibleEnd
        visibleLength = newLength
        moveVisible(start: end.addingTimeInterval(-newLength), settleNow: true)
    }

    /// Acercar (×0,5) o alejar (×2) para las acciones de accesibilidad.
    func zoom(by factor: Double) {
        setVisibleLength(visibleLength * factor)
    }

    /// Pellizco: `startLength / magnification`, con `anchorDate` fijo en la fracción `anchorFraction` del ancho.
    func pinch(startLength: TimeInterval, magnification: Double, anchorDate: Date, anchorFraction: Double) {
        guard magnification > 0 else { return }
        let newLength = Self.clampedLength(startLength / magnification)
        let fraction = min(max(anchorFraction, 0), 1)
        visibleLength = newLength
        moveVisible(start: anchorDate.addingTimeInterval(-fraction * newLength), settleNow: false)
    }

    // MARK: Navegación

    /// Mueve la ventana visible un día atrás conservando la longitud.
    func goBack() {
        let end = calendar.date(byAdding: .day, value: -1, to: visibleEnd) ?? visibleEnd.addingTimeInterval(-86_400)
        moveVisible(start: end.addingTimeInterval(-visibleLength), settleNow: true)
    }

    /// Un día adelante, sin pasar de ahora.
    func goForward() {
        guard canGoForward else { return }
        let end = calendar.date(byAdding: .day, value: 1, to: visibleEnd) ?? visibleEnd.addingTimeInterval(86_400)
        moveVisible(start: end.addingTimeInterval(-visibleLength), settleNow: true)
    }

    /// Vuelve al presente ("Ahora").
    func goToNow() {
        moveVisible(start: clock().addingTimeInterval(-visibleLength), settleNow: true)
    }

    /// Selector de fecha: la ventana termina a la misma hora del reloj de ese día (acotada a ahora).
    func select(day: Date) {
        let now = clock()
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let end = calendar.date(
            bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
        moveVisible(start: min(end, now).addingTimeInterval(-visibleLength), settleNow: true)
    }

    /// Coloca la ventana visible (sin pasar de ahora), amplía el dominio si hace falta y programa el asentado.
    private func moveVisible(start: Date, settleNow: Bool) {
        let latestStart = clock().addingTimeInterval(-visibleLength)
        let clamped = min(start, latestStart)
        if clamped != scrollPosition { scrollPosition = clamped } else { scrollDidChange() }
        coverVisibleWindow()
        scheduleSettle(after: settleNow ? .zero : Self.settleDelay)
    }

    /// El dominio X siempre contiene la ventana visible, aunque los datos lleguen después.
    private func coverVisibleWindow() {
        if visibleStart < loadedStart { loadedStart = visibleStart }
        let end = min(visibleEnd, clock())
        if end > loadedEnd { loadedEnd = end }
    }

    private func scrollDidChange() {
        let now = clock()
        let live = now.timeIntervalSince(visibleEnd) < Self.liveTolerance
        if live != isLive { isLive = live }
        let day = calendar.startOfDay(for: min(visibleEnd, now))
        if day != shownDay { shownDay = day }
        scheduleSettle(after: Self.settleDelay)
    }

    private func scheduleSettle(after delay: Duration) {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.performSettle()
        }
    }

    // MARK: Carga

    /// Carga el estado del sensor y sigue los avisos de datos nuevos y los cambios de estado hasta que se cancela la tarea.
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

    /// Datos nuevos o vuelta a primer plano: si está en vivo, la ventana avanza hasta ahora; siempre recarga.
    func refresh() async {
        if isLive {
            let start = clock().addingTimeInterval(-visibleLength)
            if start != scrollPosition { scrollPosition = start }
            coverVisibleWindow()
        }
        settleTask?.cancel()
        settleWindow()
        await reload()
    }

    /// Asienta ya, sin esperar al debounce (lo pendiente se cancela).
    func settle() async {
        settleTask?.cancel()
        await performSettle()
    }

    /// Fin del debounce: fija la ventana asentada y recarga solo si hace falta.
    private func performSettle() async {
        settleWindow()
        if needsReload { await reload() } else { recomputeVisible() }
    }

    /// Recarga si el centro de la ventana visible salió del tercio central de lo cargado (la ventana
    /// visible de la última carga), si la longitud cambió más de un 25 % o si cambió el día mostrado.
    var needsReload: Bool {
        guard let anchor = loadAnchor else { return true }
        let center = visibleStart.addingTimeInterval(visibleLength / 2)
        let lengthChange = abs(visibleLength / anchor.length - 1)
        return !(anchor.start...anchor.end).contains(center)
            || lengthChange > Self.reloadLengthChange
            || entriesDay != shownDay
    }

    private func settleWindow() {
        let start = visibleStart, end = visibleEnd
        if start != windowStart { windowStart = start }
        if end != windowEnd { windowEnd = end }
    }

    /// Lecturas y eventos de la ventana visible ampliada una longitud por cada lado (acotada a ahora).
    private func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        defer { hasLoaded = true }
        let now = clock()
        let anchorStart = visibleStart, anchorEnd = visibleEnd, length = visibleLength
        let start = anchorStart.addingTimeInterval(-length)
        let end = min(anchorEnd.addingTimeInterval(length), now)
        let range = UTCInstant(start)...UTCInstant(max(start, end))
        let day = shownDay
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let dayRange = UTCInstant(day)...UTCInstant(nextDay.addingTimeInterval(-1))
        do {
            async let latestReading = dataSource.latestEligibleReading()
            async let readings = dataSource.readings(in: range)
            async let rangeEvents = mergedEvents(in: range)
            async let dayEvents = mergedEvents(in: dayRange)
            let (newLatest, newReadings, newEvents, newDayEvents) = try await (latestReading, readings, rangeEvents, dayEvents)
            // Una carga posterior ya está en curso o terminó: estos datos son viejos.
            guard generation == loadGeneration else { return }
            latest = newLatest
            let newSegments = GlucoseSegmenter.segments(from: newReadings.compactMap(GlucosePoint.init))
            segments = newSegments
            drawSegments = GlucoseDownsampler.reduce(newSegments)
            points = newSegments.flatMap(\.points)
            gaps = GlucoseSegmenter.gaps(in: newSegments)
            marks = newEvents.compactMap(DiaryMark.init).sorted { $0.date < $1.date }
            mealResponseCache.removeAll()
            exerciseEffectCache.removeAll()
            rateEvents = RateOfChange.events(in: points.map(Self.sample))
            dayEntryCount = newDayEvents.filter { !$0.deleted }.count
            entriesDay = day
            let newStart = min(start, visibleStart)
            // Al cambiar el inicio del dominio, Swift Charts conserva el desplazamiento en puntos y no la fecha
            // (la vista saltaría). Una identidad nueva hace que la gráfica se recree leyendo `scrollPosition`.
            if newStart != loadedStart { chartIdentity += 1 }
            loadedStart = newStart
            loadedEnd = max(end, min(visibleEnd, now))
            loadAnchor = (anchorStart, anchorEnd, length)
            failure = nil
            recomputeVisible()
        } catch {
            guard generation == loadGeneration else { return }
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

    /// Puntos, estadísticas y picos de la ventana asentada, con las mismas referencias que dibuja la curva.
    private func recomputeVisible() {
        let lower = Self.firstIndex(in: points, notBefore: windowStart)
        let upper = Self.firstIndex(in: points, after: windowEnd)
        visiblePoints = lower < upper ? Array(points[lower..<upper]) : []
        let samples = visiblePoints.map { BasicStats.Sample(measuredAt: UTCInstant($0.date), valueMgdl: $0.value) }
        let bounds = referenceLow...max(referenceLow, referenceHigh)
        stats = BasicStats(samples: samples, range: bounds, window: UTCInstant(windowStart)...UTCInstant(windowEnd))
        spikes = SpikeIndex.spikes(in: samples, threshold: referenceHigh).map(TodaySpike.init)
    }

    /// Índice del primer punto con fecha `>= date` (búsqueda binaria; `points` está ordenado).
    private static func firstIndex(in points: [GlucosePoint], notBefore date: Date) -> Int {
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Índice del primer punto con fecha `> date`.
    private static func firstIndex(in points: [GlucosePoint], after date: Date) -> Int {
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date <= date { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
