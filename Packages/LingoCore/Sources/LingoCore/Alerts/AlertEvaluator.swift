import Foundation

/// Evaluador puro de alertas (T-24): sin reloj, sin E/S ni notificaciones. El llamador pasa las lecturas elegibles
/// recientes, el instante actual, las líneas del rango de referencia y el `AlertState` anterior, y guarda el nuevo.
///
/// Reglas (ver `docs/T-24.md`):
/// - **Alta / baja**: la última lectura (de hace ≤ 5 min) está por encima de `high` o por debajo de `low`.
///   Se avisa al entrar en la condición; mientras se mantiene, solo se repite tras el silencio entre avisos.
///   La condición se rearma al volver al rango con un margen de 5 mg/dL (evita avisos por el ruido del sensor
///   alrededor de la línea); al salir de nuevo se avisa de inmediato.
/// - **Subida / bajada rápida**: pendiente ≥ `rateThreshold` (o ≤ −`rateThreshold`) en la ventana de
///   `rateWindowMinutes` que termina en la última lectura. Pendiente = (media de valores de los 5 últimos minutos −
///   media de los 5 primeros) / (diferencia entre las horas medias de los dos bloques, en minutos). Cada bloque
///   necesita ≥ 3 lecturas. Siempre respeta el silencio entre avisos. Si en la misma evaluación se avisa de alta
///   (o baja), la subida (o bajada) rápida no se avisa aparte: su pendiente va en el mensaje de alta o baja.
/// - **Sin datos**: sesión activa y más de `noDataAfterMinutes` desde la última lectura elegible.
///   Siempre respeta el silencio entre avisos (60 min por defecto).
/// - **Horas de silencio** (hora local): no se avisa, salvo la baja si `lowOverridesQuietHours`. La condición se
///   sigue registrando, así que al terminar el silencio se avisa si continúa y el silencio entre avisos lo permite.
/// - Con el interruptor general o el del tipo apagado no se avisa, pero el estado se sigue actualizando.
public enum AlertEvaluator {
    /// Antigüedad máxima de la última lectura para evaluar alta, baja y pendiente.
    public static let freshnessSeconds: Int64 = 5 * 60
    /// Margen para rearmar alta y baja tras volver al rango.
    public static let rearmMarginMgdl = 5
    /// Duración de cada bloque de la pendiente.
    public static let rateBlockSeconds: Int64 = 5 * 60
    public static let minSamplesPerBlock = 3

    /// - Parameters:
    ///   - samples: lecturas elegibles recientes (≥ ventana de la pendiente), ordenadas por hora.
    ///   - lastReadingAt: última lectura elegible conocida si es anterior a `samples` (para "sin datos" con ventanas
    ///     largas); se usa la más reciente de las dos. Sin ninguna, "sin datos" no se evalúa.
    ///   - sessionActive: sensor en sesión viva (transmitiendo, desactualizado o reconectando).
    ///   - timeZone: zona para las horas de silencio.
    public static func evaluate(
        samples: [BasicStats.Sample],
        now: UTCInstant,
        low: Int,
        high: Int,
        settings: AlertSettings,
        state: AlertState,
        sessionActive: Bool = true,
        lastReadingAt: UTCInstant? = nil,
        timeZone: TimeZone = .current
    ) -> (alerts: [AlertEvent], state: AlertState) {
        let s = settings.normalized()
        let sorted = samples.filter { $0.measuredAt <= now }.sorted { $0.measuredAt < $1.measuredAt }
        let latest = sorted.last.flatMap { now.epochSeconds - $0.measuredAt.epochSeconds <= freshnessSeconds ? $0 : nil }
        let slope = latest.flatMap { slope(of: sorted, endingAt: $0.measuredAt, windowMinutes: s.rateWindowMinutes) }
        let quiet = s.quietHours?.contains(minuteOfDay: localMinute(of: now, in: timeZone)) ?? false

        var next = state
        var fired: [AlertKind: UTCInstant] = [:]

        func allowed(_ kind: AlertKind) -> Bool {
            s.isEnabled && s.isEnabled(kind) && (!quiet || (kind == .low && s.lowOverridesQuietHours))
        }
        func cooled(_ kind: AlertKind) -> Bool {
            guard let last = state.lastFired[kind] else { return true }
            return now.epochSeconds - last.epochSeconds >= Int64(s.cooldown(for: kind)) * 60
        }
        /// `condition`: `true` se cumple, `false` se despeja, `nil` sin cambios (banda de rearme o sin datos frescos).
        func apply(_ kind: AlertKind, _ condition: Bool?, since: @autoclosure () -> UTCInstant?, reentryBypassesCooldown: Bool) {
            switch condition {
            case .none:
                return
            case .some(false):
                next.activeSince[kind] = nil
            case .some(true):
                let wasActive = state.activeSince[kind] != nil
                let start = state.activeSince[kind] ?? since() ?? now
                next.activeSince[kind] = start
                let due = wasActive || !reentryBypassesCooldown ? cooled(kind) : true
                if allowed(kind), due { fired[kind] = start }
            }
        }

        // Alta y baja.
        let highCondition: Bool? = latest.map { $0.valueMgdl > high ? true : ($0.valueMgdl <= high - rearmMarginMgdl ? false : nil) } ?? nil
        let lowCondition: Bool? = latest.map { $0.valueMgdl < low ? true : ($0.valueMgdl >= low + rearmMarginMgdl ? false : nil) } ?? nil
        apply(.high, highCondition, since: runStart(sorted) { $0 > high }, reentryBypassesCooldown: true)
        apply(.low, lowCondition, since: runStart(sorted) { $0 < low }, reentryBypassesCooldown: true)

        // Pendiente.
        let windowStart = latest.map { $0.measuredAt.adding(seconds: -Int64(s.rateWindowMinutes) * 60) }
        let risingCondition: Bool? = slope.map { $0 >= s.rateThreshold } ?? (latest == nil ? nil : false)
        let fallingCondition: Bool? = slope.map { $0 <= -s.rateThreshold } ?? (latest == nil ? nil : false)
        apply(.risingFast, risingCondition, since: windowStart, reentryBypassesCooldown: false)
        apply(.fallingFast, fallingCondition, since: windowStart, reentryBypassesCooldown: false)

        // Sin datos.
        let reference = [sorted.last?.measuredAt, lastReadingAt].compactMap { $0 }.max()
        let noDataCondition: Bool
        if sessionActive, let reference {
            noDataCondition = now.epochSeconds - reference.epochSeconds > Int64(s.noDataAfterMinutes) * 60
        } else {
            noDataCondition = false
        }
        apply(.noData, noDataCondition, since: reference, reentryBypassesCooldown: false)

        // La pendiente va dentro del aviso de alta o baja.
        if fired[.high] != nil, fired[.risingFast] != nil { fired[.risingFast] = nil; next.lastFired[.risingFast] = now }
        if fired[.low] != nil, fired[.fallingFast] != nil { fired[.fallingFast] = nil; next.lastFired[.fallingFast] = now }

        let alerts = AlertKind.allCases.compactMap { kind -> AlertEvent? in
            guard let since = fired[kind] else { return nil }
            next.lastFired[kind] = now
            return AlertEvent(
                kind: kind, at: now,
                value: kind == .noData ? nil : latest?.valueMgdl,
                slopePerMinute: kind == .noData ? nil : slope,
                since: since)
        }
        return (alerts, next)
    }

    /// Pendiente en mg/dL por minuto de la ventana que termina en `end`, o `nil` si algún bloque tiene menos de
    /// `minSamplesPerBlock` lecturas.
    public static func slope(of sorted: [BasicStats.Sample], endingAt end: UTCInstant, windowMinutes: Int) -> Double? {
        let start = end.epochSeconds - Int64(windowMinutes) * 60
        let first = sorted.filter { $0.measuredAt.epochSeconds >= start && $0.measuredAt.epochSeconds < start + rateBlockSeconds }
        let last = sorted.filter { $0.measuredAt.epochSeconds > end.epochSeconds - rateBlockSeconds && $0.measuredAt <= end }
        guard first.count >= minSamplesPerBlock, last.count >= minSamplesPerBlock else { return nil }
        func mean(_ block: [BasicStats.Sample]) -> (value: Double, seconds: Double) {
            let n = Double(block.count)
            return (Double(block.reduce(0) { $0 + $1.valueMgdl }) / n,
                    Double(block.reduce(Int64(0)) { $0 + $1.measuredAt.epochSeconds - start }) / n)
        }
        let a = mean(first), b = mean(last)
        let minutes = (b.seconds - a.seconds) / 60
        guard minutes >= 5 else { return nil }
        return (b.value - a.value) / minutes
    }

    /// Minuto del día (0…1439) en la zona dada.
    public static func localMinute(of instant: UTCInstant, in timeZone: TimeZone) -> Int {
        let offset = Int64(timeZone.secondsFromGMT(for: instant.date))
        let seconds = ((instant.epochSeconds + offset) % 86_400 + 86_400) % 86_400
        return Int(seconds / 60)
    }

    /// Primera lectura de la racha final que cumple `predicate`.
    private static func runStart(_ sorted: [BasicStats.Sample], _ predicate: (Int) -> Bool) -> UTCInstant? {
        var start: UTCInstant?
        for sample in sorted.reversed() {
            guard predicate(sample.valueMgdl) else { break }
            start = sample.measuredAt
        }
        return start
    }
}
