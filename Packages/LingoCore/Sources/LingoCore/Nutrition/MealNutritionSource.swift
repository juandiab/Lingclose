/// De dónde salen los nutrientes base de una comida. Solo identificadores de proveedor y modelo,
/// nunca claves ni respuestas completas.
///
/// JSON: `{"type": "llm" | "label" | "manual", "provider": …, "model": …}` (`provider`/`model` solo en
/// `llm` y `label`).
public enum MealNutritionSource: Sendable, Hashable, Codable {
    /// Comida reconocida y estimada por un modelo.
    case llm(provider: String, model: String)
    /// Etiqueta nutricional leída por un modelo.
    case label(provider: String, model: String)
    /// Cifras escritas por el usuario sin análisis.
    case manual

    /// Identificador estable (`type` del JSON).
    public var typeName: String {
        switch self {
        case .llm: "llm"
        case .label: "label"
        case .manual: "manual"
        }
    }

    enum CodingKeys: String, CodingKey { case type, provider, model }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "llm":
            self = .llm(provider: try c.decode(String.self, forKey: .provider), model: try c.decode(String.self, forKey: .model))
        case "label":
            self = .label(provider: try c.decode(String.self, forKey: .provider), model: try c.decode(String.self, forKey: .model))
        case "manual":
            self = .manual
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "source desconocida: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .llm(let provider, let model), .label(let provider, let model):
            try c.encode(provider, forKey: .provider)
            try c.encode(model, forKey: .model)
        case .manual:
            break
        }
    }
}
