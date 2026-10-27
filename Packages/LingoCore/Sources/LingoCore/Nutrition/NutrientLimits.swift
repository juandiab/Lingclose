/// Límites de plausibilidad por **base** (una porción, 100 g o 100 ml). Fuera de ellos la respuesta se rechaza.
public enum NutrientLimits {
    public static let kcal = 0.0...5_000.0
    public static let gramsPerNutrient = 0.0...2_000.0
    public static let basisGrams = 0.0...5_000.0
    public static let confidence = 0.0...1.0
    /// Multiplicador de porciones de la UI.
    public static let portionMultiplier = 1.0...5.0
    public static let portionStep = 0.1

    public static func range(for field: NutrientField) -> ClosedRange<Double> {
        field == .kcal ? kcal : gramsPerNutrient
    }
}
