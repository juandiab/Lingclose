/// Reglas puras del slider de porciones y de las correcciones manuales. La UI solo las muestra.
public enum PortionAdjustment {
    /// Lleva `m` al paso de 0,1 y al rango 0,5…5,0. Primero redondea a 1 decimal con
    /// `.toNearestOrAwayFromZero` (1,25 → 1,3; 1,24 → 1,2) y después acota (0,3 → 0,5; 5,3 → 5,0).
    /// Un valor no finito vuelve a 1,0 (la base).
    public static func clamp(_ m: Double) -> Double {
        guard m.isFinite else { return NutrientLimits.defaultPortionMultiplier }
        // Paso 0,1 = décimas. Se multiplica y divide por 10 (no por 0,1) para que el resultado sea
        // exactamente el literal de 1 decimal: 13 / 10 == 1.3.
        let rounded = (m * 10).rounded(.toNearestOrAwayFromZero) / 10
        return min(max(rounded, NutrientLimits.portionMultiplier.lowerBound), NutrientLimits.portionMultiplier.upperBound)
    }

    /// `overrides[f] ?? base[f] * multiplier`, campo a campo. Los desconocidos siguen desconocidos.
    public static func adjusted(_ base: Nutrients, multiplier: Double, overrides: Nutrients) -> Nutrients {
        base.scaled(by: multiplier).overridden(by: overrides)
    }

    /// Texto legible: kcal entero; gramos con 1 decimal (coma decimal) si no es entero tras redondear a
    /// 1 decimal. `nil` → `nil` (la UI pone "Desconocido", nunca 0).
    public static func display(_ value: Double?, field: NutrientField) -> String? {
        guard let value, value.isFinite else { return nil }
        if field == .kcal {
            return String(Int64(value.rounded(.toNearestOrAwayFromZero)))
        }
        let tenths = Int64((value * 10).rounded(.toNearestOrAwayFromZero))
        let whole = tenths / 10, fraction = abs(tenths % 10)
        if fraction == 0 { return String(whole) }
        let sign = tenths < 0 && whole == 0 ? "-" : ""
        return "\(sign)\(whole),\(fraction)"
    }
}
