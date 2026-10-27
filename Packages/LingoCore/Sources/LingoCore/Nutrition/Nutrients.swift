import Foundation

/// Cuatro nutrientes de una comida. `nil` significa **desconocido** (ilegible o no estimado) y nunca se
/// convierte en 0: un cero es un valor conocido.
public struct Nutrients: Sendable, Hashable, Codable {
    public var kcal: Double?
    public var carbsG: Double?
    public var proteinG: Double?
    public var fatG: Double?

    public init(kcal: Double? = nil, carbsG: Double? = nil, proteinG: Double? = nil, fatG: Double? = nil) {
        self.kcal = kcal
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fatG = fatG
    }

    public static let unknown = Nutrients()

    /// `true` si no hay ninguna cifra conocida.
    public var isUnknown: Bool { kcal == nil && carbsG == nil && proteinG == nil && fatG == nil }

    /// Multiplica cada valor conocido; los desconocidos siguen desconocidos. Siempre desde la base
    /// (`base.scaled(by: m)`), nunca sobre un valor ya escalado.
    public func scaled(by multiplier: Double) -> Nutrients {
        Nutrients(kcal: kcal.map { $0 * multiplier }, carbsG: carbsG.map { $0 * multiplier },
                  proteinG: proteinG.map { $0 * multiplier }, fatG: fatG.map { $0 * multiplier })
    }

    /// Cada campo: el de `overrides` si existe, si no el propio.
    public func overridden(by overrides: Nutrients) -> Nutrients {
        Nutrients(kcal: overrides.kcal ?? kcal, carbsG: overrides.carbsG ?? carbsG,
                  proteinG: overrides.proteinG ?? proteinG, fatG: overrides.fatG ?? fatG)
    }

    enum CodingKeys: String, CodingKey {
        case kcal
        case carbsG = "carbs_g"
        case proteinG = "protein_g"
        case fatG = "fat_g"
    }
}
