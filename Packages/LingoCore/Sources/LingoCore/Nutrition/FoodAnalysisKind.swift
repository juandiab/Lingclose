/// Qué reconoció el modelo en la foto o la descripción. Lo decide el modelo; el usuario no lo elige antes.
public enum FoodAnalysisKind: String, Sendable, Hashable, Codable {
    case food
    case nutritionLabel = "nutrition_label"
    case notFood = "not_food"
}
