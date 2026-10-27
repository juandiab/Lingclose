import LingoCore

extension NutrientField {
    var title: String {
        switch self {
        case .kcal: String(localized: "meal.field.kcal", defaultValue: "Calorías")
        case .carbsG: String(localized: "meal.field.carbs", defaultValue: "Carbohidratos")
        case .proteinG: String(localized: "meal.field.protein", defaultValue: "Proteínas")
        case .fatG: String(localized: "meal.field.fat", defaultValue: "Grasas")
        }
    }

    var unit: String {
        self == .kcal ? "kcal" : "g"
    }
}
