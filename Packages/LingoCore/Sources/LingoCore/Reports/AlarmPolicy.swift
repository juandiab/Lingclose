/// Lógica pura de alarmas (D-12): umbrales, histéresis por alarma y "sin datos". Sin reloj, sin
/// notificaciones y sin E/S: el llamador pasa el instante actual y conserva el `AlarmState`.
/// LingoScan es bienestar, no un dispositivo médico; estas decisiones son informativas.

public enum AlarmKind: String, Sendable, Hashable, Codable, CaseIterable {
    case low, high, noData
}

/// Umbrales y activación editables por el usuario. Valores iniciales: D-12.
public struct AlarmSettings: Sendable, Hashable, Codable {
    public static let lowRange = 40...120
    public static let highRange = 120...400
    public static let noDataRange = 10...120

    public var lowMgdl: Int
    public var highMgdl: Int
    public var noDataMinutes: Int
    public var lowEnabled: Bool
    public var highEnabled: Bool
    public var noDataEnabled: Bool

    public init(
        lowMgdl: Int = 70, highMgdl: Int = 180, noDataMinutes: Int = 20,
        lowEnabled: Bool = true, highEnabled: Bool = true, noDataEnabled: Bool = true
    ) {
        self.lowMgdl = lowMgdl
        self.highMgdl = highMgdl
        self.noDataMinutes = noDataMinutes
        self.lowEnabled = lowEnabled
        self.highEnabled = highEnabled
        self.noDataEnabled = noDataEnabled
    }

    public static let `default` = AlarmSettings()

    /// Acota cada valor a su rango y garantiza `low < high`.
    public func normalized() -> AlarmSettings {
        var s = self
        s.lowMgdl = min(max(lowMgdl, Self.lowRange.lowerBound), Self.lowRange.upperBound)
        s.highMgdl = min(max(highMgdl, Self.highRange.lowerBound), Self.highRange.upperBound)
        if s.highMgdl <= s.lowMgdl { s.highMgdl = s.lowMgdl + 1 }
        s.noDataMinutes = min(max(noDataMinutes, Self.noDataRange.lowerBound), Self.noDataRange.upperBound)
        return s
    }
}

/// Una lectura que puede alimentar alarmas: elegible, no sintética, no borrada y en vivo
/// (el relleno histórico nunca dispara). Se construye pasando por `HealthExportable`.
public struct AlarmSample: Sendable, Hashable {
    public let valueMgdl: Int
    public let measuredAt: UTCInstant
    public let lifeCount: Int
    public let sessionID: String

    public init(valueMgdl: Int, measuredAt: UTCInstant, lifeCount: Int = 0, sessionID: String = "") {
        self.valueMgdl = valueMgdl
        self.measuredAt = measuredAt
        self.lifeCount = lifeCount
        self.sessionID = sessionID
    }

    public init?(reading: GlucoseReading) {
        guard let e = HealthExportable(reading: reading), e.origin == .live else { return nil }
        self.init(valueMgdl: e.valueMgdl, measuredAt: e.measuredAt, lifeCount: e.lifeCount, sessionID: e.sessionID)
    }
}

public enum AlarmDecision: Sendable, Hashable {
    case none
    /// `valueMgdl` es `nil` en "sin datos".
    case fire(AlarmKind, valueMgdl: Int?)
}

/// Memoria mínima entre evaluaciones.
public struct AlarmState: Sendable, Hashable {
    public private(set) var lastFired: [AlarmKind: UTCInstant]
    public private(set) var lastValid: UTCInstant?
    public private(set) var isPaused: Bool

    public init(lastFired: [AlarmKind: UTCInstant] = [:], lastValid: UTCInstant? = nil, isPaused: Bool = false) {
        self.lastFired = lastFired
        self.lastValid = lastValid
        self.isPaused = isPaused
    }

    /// En pausa no hay alarmas ni "sin datos"; al reanudar se parte de cero.
    public func paused(_ paused: Bool) -> AlarmState {
        paused ? AlarmState(lastFired: lastFired, lastValid: nil, isPaused: true)
               : AlarmState(lastFired: lastFired, lastValid: lastValid, isPaused: false)
    }

    func recording(_ kind: AlarmKind, at now: UTCInstant) -> AlarmState {
        var copy = self
        copy.lastFired[kind] = now
        return copy
    }

    func armed(lastValid at: UTCInstant) -> AlarmState {
        var copy = self
        copy.lastValid = at
        return copy
    }
}

public enum AlarmPolicy {
    /// Mismo tipo de alarma: no se repite antes de este plazo (D-12: 15 min).
    public static let hysteresisSeconds: Int64 = 15 * 60

    /// Evalúa una lectura válida. Siempre arma "sin datos" a partir de su hora de medición.
    public static func evaluate(
        sample: AlarmSample, now: UTCInstant, settings: AlarmSettings, state: AlarmState
    ) -> (decision: AlarmDecision, state: AlarmState) {
        guard !state.isPaused else { return (.none, state) }
        let settings = settings.normalized()
        // Una lectura de relleno antigua no arma ni dispara nada.
        let age = now.epochSeconds - sample.measuredAt.epochSeconds
        guard age <= Int64(settings.noDataMinutes) * 60 else { return (.none, state) }

        var next = state
        if state.lastValid.map({ sample.measuredAt > $0 }) ?? true { next = next.armed(lastValid: sample.measuredAt) }

        let kind: AlarmKind?
        if sample.valueMgdl < settings.lowMgdl, settings.lowEnabled { kind = .low }
        else if sample.valueMgdl > settings.highMgdl, settings.highEnabled { kind = .high }
        else { kind = nil }

        guard let kind, canFire(kind, now: now, state: state) else { return (.none, next) }
        return (.fire(kind, valueMgdl: sample.valueMgdl), next.recording(kind, at: now))
    }

    /// Instante en que debe saltar "sin datos" tras la última lectura válida.
    public static func noDataDeadline(lastValid: UTCInstant, settings: AlarmSettings) -> UTCInstant {
        lastValid.adding(seconds: Int64(settings.normalized().noDataMinutes) * 60)
    }

    /// "Sin datos": dispara si pasaron `noDataMinutes` desde la última lectura válida y la
    /// histéresis lo permite. Sin lectura previa no hay nada que vigilar.
    public static func evaluateNoData(
        now: UTCInstant, settings: AlarmSettings, state: AlarmState
    ) -> (decision: AlarmDecision, state: AlarmState) {
        guard !state.isPaused, settings.noDataEnabled, let last = state.lastValid,
              now >= noDataDeadline(lastValid: last, settings: settings),
              canFire(.noData, now: now, state: state)
        else { return (.none, state) }
        return (.fire(.noData, valueMgdl: nil), state.recording(.noData, at: now))
    }

    private static func canFire(_ kind: AlarmKind, now: UTCInstant, state: AlarmState) -> Bool {
        guard let last = state.lastFired[kind] else { return true }
        return now.epochSeconds - last.epochSeconds >= hysteresisSeconds
    }
}
