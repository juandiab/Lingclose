/// Consejos por reglas para una alerta (T-25). Deterministas, sin red ni reloj: misma entrada, misma salida.
/// Pensados para una persona **sin diabetes** que no usa insulina ni medicación para la glucosa: bienestar, no
/// consejo médico. Ningún texto habla de insulina, fármacos, dosis ni diagnósticos (lo comprueban los tests).
///
/// Reglas (en orden; se devuelven los primeros `limit` sin repetir):
/// - **Sin datos**: Bluetooth y acercar el teléfono.
/// - **Alta / subida rápida** con comida en las últimas 2 h: de día, caminar y agua; de noche, agua y esperar.
///   Si la comida tuvo ≥ 45 g de carbohidratos, la idea para la próxima comida.
/// - **Alta / subida rápida** sin comida reciente: anotar estrés, sueño o café; de día, movimiento suave; de noche,
///   pausa y respiración. Si la alta ya va bajando (pendiente ≤ −1), primero "ya va bajando". Con el tiempo en rango del día
///   < 50 %, se añade comentarlo con un profesional si se repite.
/// - **Baja**: primero síntomas → carbohidratos y mirar en 15 min; luego, tras ejercicio reciente, el consejo de
///   entrenamiento; si no, la compresión del sensor al dormir.
/// - **Bajada rápida**: tras ejercicio, hidratarse y algo ligero; de noche, compresión del sensor; tras comer, es la
///   bajada del pico; si no, mirar en 15 min y algo ligero si no has comido en horas.
public enum CoachingRules {
    private typealias C = CoachingCatalog

    /// Comida "reciente": hasta 2 h.
    public static let recentMealMinutes = 120
    /// Ejercicio "reciente": hasta 90 min después de terminar.
    public static let recentExerciseMinutes = 90
    /// Carbohidratos a partir de los que se sugiere la idea para la próxima comida.
    public static let largeMealCarbsG = 45.0
    /// Tiempo en rango del día por debajo del cual se sugiere comentarlo con un profesional si se repite.
    public static let lowTimeInRange = 0.5

    public static func tips(for context: CoachingContext, limit: Int = 2) -> [CoachingTip] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        let unique = candidates(for: context).filter { seen.insert($0.id).inserted }
        return Array(unique.prefix(limit))
    }

    /// Consejo por id (para reconstruir los mostrados en una tarjeta guardada).
    public static func tip(id: String) -> CoachingTip? { CoachingCatalog.all.first { $0.id == id } }

    // MARK: - Reglas

    static func candidates(for c: CoachingContext) -> [CoachingTip] {
        switch c.kind {
        case .noData:
            return [C.noDataBluetooth, C.noDataPhone]
        case .high, .risingFast:
            return elevated(c)
        case .low:
            return [C.lowSymptoms] + (c.hasRecentExercise ? [C.afterExercise] : []) + [C.lowCompression]
        case .fallingFast:
            if c.hasRecentExercise { return [C.afterExercise, C.fallingWatch] }
            if c.isNight { return [C.lowCompression, C.fallingWatch] }
            if c.hasRecentMeal { return [C.fallingWatch, C.waterNoSugar] }
            return [C.fallingWatch, C.fallingSnack]
        }
    }

    private static func elevated(_ c: CoachingContext) -> [CoachingTip] {
        var list: [CoachingTip] = []
        if c.kind == .high, let slope = c.slopePerMinute, slope <= -1 {
            list.append(C.alreadyFalling)
        }
        if c.hasRecentMeal {
            list += c.isNight ? [C.waterNoSugar, C.risingWait] : [C.walkAfterMeal, C.waterNoSugar]
            if let carbs = c.lastMealCarbsG, carbs >= largeMealCarbsG { list.append(C.mealOrder) }
        } else {
            list += [C.noteContext, c.isNight ? C.restBreath : C.moveLight,
                     C.risingWait]
        }
        if c.kind == .high, let tir = c.timeInRangeToday, tir < lowTimeInRange {
            list.append(C.highPersisting)
        }
        return list
    }
}
