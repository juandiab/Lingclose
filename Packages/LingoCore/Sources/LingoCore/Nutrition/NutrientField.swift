/// Identifica uno de los cuatro nutrientes (para correcciones manuales campo a campo y mensajes).
public enum NutrientField: String, Sendable, Hashable, Codable, CaseIterable {
    case kcal
    case carbsG = "carbs_g"
    case proteinG = "protein_g"
    case fatG = "fat_g"
}

extension Nutrients {
    public subscript(field: NutrientField) -> Double? {
        get {
            switch field {
            case .kcal: kcal
            case .carbsG: carbsG
            case .proteinG: proteinG
            case .fatG: fatG
            }
        }
        set {
            switch field {
            case .kcal: kcal = newValue
            case .carbsG: carbsG = newValue
            case .proteinG: proteinG = newValue
            case .fatG: fatG = newValue
            }
        }
    }
}
