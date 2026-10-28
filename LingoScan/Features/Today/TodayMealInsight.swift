import LingoCore

/// Una comida de la ventana visible con su respuesta de glucosa (T-23).
struct TodayMealInsight: Sendable, Hashable, Identifiable {
    let mark: DiaryMark
    let response: MealResponse

    var id: DiaryMark.ID { mark.id }

    /// Texto de la comida si lo tiene; si no, "Comida".
    var name: String { mark.text.flatMap { $0.isEmpty ? nil : $0 } ?? mark.kind.title }
}
