import LingoCore

/// Resumen de la ventana visible para la fila "Insights" de Hoy (T-23): subidas y bajadas rápidas y la mejor
/// y la peor respuesta a comida según `MealResponse.score`. Informativo, no médico.
struct TodayInsights: Sendable, Hashable {
    let rateEvents: [RateEvent]
    /// Comidas visibles con respuesta, en orden de hora.
    let meals: [TodayMealInsight]

    var risingCount: Int { rateEvents.filter { $0.direction == .rising }.count }
    var fallingCount: Int { rateEvents.filter { $0.direction == .falling }.count }

    /// Comida con la puntuación más alta (en empate, la primera).
    var best: TodayMealInsight? {
        meals.reduce(nil) { result, meal in
            guard let result else { return meal }
            return meal.response.score > result.response.score ? meal : result
        }
    }

    /// Comida con la puntuación más baja distinta de `best` (en empate, la última); `nil` con una sola comida.
    var worst: TodayMealInsight? {
        let others = meals.filter { $0.id != best?.id }
        return others.reduce(nil) { result, meal in
            guard let result else { return meal }
            return meal.response.score <= result.response.score ? meal : result
        }
    }

    var isEmpty: Bool { rateEvents.isEmpty && meals.isEmpty }
}
