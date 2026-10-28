/// Lo que las reglas de consejos saben de una alerta (T-25): tipo, valor, pendiente, la última comida y el último
/// ejercicio del diario, la hora local y el tiempo en rango del día. Solo agregados: nada de lecturas sueltas ni
/// identificadores. Es `Codable` para guardarlo con la tarjeta "Qué hacer" hasta la siguiente alerta.
public struct CoachingContext: Sendable, Hashable, Codable {
    public var kind: AlertKind
    /// Última lectura en mg/dL; `nil` en "sin datos".
    public var value: Int?
    /// Pendiente en mg/dL por minuto, si se pudo calcular.
    public var slopePerMinute: Double?
    /// Minutos desde la última comida anotada (si la hay en el día).
    public var minutesSinceLastMeal: Int?
    /// Carbohidratos de esa comida, en gramos, si se conocen.
    public var lastMealCarbsG: Double?
    /// Minutos desde el final del último ejercicio anotado.
    public var minutesSinceLastExercise: Int?
    /// Hora local de la alerta, 0…23.
    public var hour: Int
    /// Fracción 0…1 del día con lecturas en rango, si hay datos suficientes.
    public var timeInRangeToday: Double?

    public init(
        kind: AlertKind,
        value: Int? = nil,
        slopePerMinute: Double? = nil,
        minutesSinceLastMeal: Int? = nil,
        lastMealCarbsG: Double? = nil,
        minutesSinceLastExercise: Int? = nil,
        hour: Int,
        timeInRangeToday: Double? = nil
    ) {
        self.kind = kind
        self.value = value
        self.slopePerMinute = slopePerMinute
        self.minutesSinceLastMeal = minutesSinceLastMeal
        self.lastMealCarbsG = lastMealCarbsG
        self.minutesSinceLastExercise = minutesSinceLastExercise
        self.hour = min(max(hour, 0), 23)
        self.timeInRangeToday = timeInRangeToday
    }

    /// Comida en las últimas 2 h.
    public var hasRecentMeal: Bool { minutesSinceLastMeal.map { (0...CoachingRules.recentMealMinutes).contains($0) } ?? false }
    /// Ejercicio terminado hace ≤ 90 min (o en curso).
    public var hasRecentExercise: Bool {
        minutesSinceLastExercise.map { (0...CoachingRules.recentExerciseMinutes).contains($0) } ?? false
    }
    /// Noche: de 23:00 a 5:59.
    public var isNight: Bool { hour >= 23 || hour < 6 }
}
