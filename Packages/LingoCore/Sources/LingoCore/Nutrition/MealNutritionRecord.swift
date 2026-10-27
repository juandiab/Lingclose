/// Lo que se guarda junto a un evento `meal` (tabla `meal_nutrition`, migración v2). El contrato
/// compartido del `.lingoscan` no cambia: el evento solo lleva `carbs_g` (= `effectiveNutrients.carbsG`)
/// y `text`. Un evento `meal` sin registro sigue siendo válido.
public struct MealNutritionRecord: Sendable, Hashable, Codable {
    public var eventID: String
    public var source: MealNutritionSource
    /// `food` o `nutrition_label` (nunca `not_food`).
    public var kind: FoodAnalysisKind
    public var name: String?
    public var basis: PortionBasis
    /// La base original, intacta. Nunca se reescribe con valores escalados.
    public var baseNutrients: Nutrients
    /// Porciones consumidas sobre la base: 1,0…5,0, paso 0,1 (`PortionAdjustment.clamp`).
    public var multiplier: Double
    /// Correcciones manuales campo a campo sobre el valor ya ajustado; `nil` = sin corrección.
    public var overrides: Nutrients
    public var assumptions: String?
    public var confidence: Double?
    public var analyzedAt: UTCInstant?
    public var updatedAt: UTCInstant

    public init(
        eventID: String,
        source: MealNutritionSource,
        kind: FoodAnalysisKind,
        name: String? = nil,
        basis: PortionBasis,
        baseNutrients: Nutrients,
        multiplier: Double = 1.0,
        overrides: Nutrients = .unknown,
        assumptions: String? = nil,
        confidence: Double? = nil,
        analyzedAt: UTCInstant? = nil,
        updatedAt: UTCInstant
    ) {
        self.eventID = eventID
        self.source = source
        self.kind = kind
        self.name = name
        self.basis = basis
        self.baseNutrients = baseNutrients
        self.multiplier = multiplier
        self.overrides = overrides
        self.assumptions = assumptions
        self.confidence = confidence
        self.analyzedAt = analyzedAt
        self.updatedAt = updatedAt
    }

    /// `overrides[f] ?? base[f] * multiplier`, campo a campo. Siempre desde la base: nunca acumula.
    public var effectiveNutrients: Nutrients {
        PortionAdjustment.adjusted(baseNutrients, multiplier: multiplier, overrides: overrides)
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case source
        case kind
        case name
        case basis
        case baseNutrients = "base_nutrients"
        case multiplier
        case overrides
        case assumptions
        case confidence
        case analyzedAt = "analyzed_at_utc"
        case updatedAt = "updated_at_utc"
    }
}
