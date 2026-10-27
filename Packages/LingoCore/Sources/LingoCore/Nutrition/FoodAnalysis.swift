/// Propuesta estructurada del modelo (T-21), ya validada por `FoodAnalysisParser`. Es una **propuesta
/// editable**: no se guarda sola.
public struct FoodAnalysis: Sendable, Hashable, Codable {
    public var kind: FoodAnalysisKind
    /// Nombre del alimento o producto; `nil` si no se reconoció.
    public var name: String?
    /// Base de los nutrientes (`nil` solo para `notFood`).
    public var basis: PortionBasis?
    /// Nutrientes por `basis`. Desconocido = `nil`, nunca 0.
    public var baseNutrients: Nutrients
    /// 0–1; `nil` si el modelo no la dio.
    public var confidence: Double?
    /// Supuestos breves del modelo (tamaño de ración, preparación, valores no legibles…).
    public var assumptions: String?
    /// Campos de la etiqueta que no se pudieron leer, con nombre tal cual los nombró el modelo.
    public var unreadableFields: [String]

    public init(kind: FoodAnalysisKind, name: String? = nil, basis: PortionBasis? = nil,
                baseNutrients: Nutrients = .unknown, confidence: Double? = nil, assumptions: String? = nil,
                unreadableFields: [String] = []) {
        self.kind = kind
        self.name = name
        self.basis = basis
        self.baseNutrients = baseNutrients
        self.confidence = confidence
        self.assumptions = assumptions
        self.unreadableFields = unreadableFields
    }

    /// `true` cuando hay al menos una cifra con la que el ajuste de porciones tiene sentido.
    public var hasAnyNutrient: Bool { !baseNutrients.isUnknown }

    enum CodingKeys: String, CodingKey {
        case kind, name, basis
        case baseNutrients = "nutrients"
        case confidence, assumptions
        case unreadableFields = "unreadable"
    }
}
