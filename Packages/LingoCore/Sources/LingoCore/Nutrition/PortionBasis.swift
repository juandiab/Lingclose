/// A qué cantidad se refieren los nutrientes **base**. No es la cantidad consumida: esa la fija el
/// multiplicador de porciones (1,0–5,0) sobre esta base.
public enum PortionBasis: Sendable, Hashable, Codable {
    /// Etiqueta: valores por 100 g.
    case per100g
    /// Etiqueta: valores por 100 ml.
    case per100ml
    /// Etiqueta: valores por porción declarada (p. ej. "1 barra (40 g)").
    case perServing(description: String?, grams: Double?)
    /// Comida reconocida: porción concreta que propone el modelo (p. ej. "1 arepa mediana (80 g)").
    case estimatedServing(description: String?, grams: Double?)

    public var isLabel: Bool {
        switch self {
        case .per100g, .per100ml, .perServing: true
        case .estimatedServing: false
        }
    }

    public var description: String? {
        switch self {
        case .per100g, .per100ml: nil
        case .perServing(let d, _), .estimatedServing(let d, _): d
        }
    }

    public var grams: Double? {
        switch self {
        case .per100g: 100
        case .per100ml: nil
        case .perServing(_, let g), .estimatedServing(_, let g): g
        }
    }

    /// Identificador estable (`type` del JSON del modelo y de la base de datos).
    public var typeName: String {
        switch self {
        case .per100g: "per_100g"
        case .per100ml: "per_100ml"
        case .perServing: "per_serving"
        case .estimatedServing: "estimated_serving"
        }
    }

    public init?(typeName: String, description: String?, grams: Double?) {
        switch typeName {
        case "per_100g": self = .per100g
        case "per_100ml": self = .per100ml
        case "per_serving": self = .perServing(description: description, grams: grams)
        case "estimated_serving": self = .estimatedServing(description: description, grams: grams)
        default: return nil
        }
    }

    enum CodingKeys: String, CodingKey { case type, description, grams }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        guard let basis = PortionBasis(typeName: type, description: try c.decodeIfPresent(String.self, forKey: .description),
                                       grams: try c.decodeIfPresent(Double.self, forKey: .grams)) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "basis desconocida: \(type)")
        }
        self = basis
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        try c.encode(description, forKey: .description)
        try c.encode(grams, forKey: .grams)
    }
}
