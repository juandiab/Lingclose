/// Límites de una sugerencia de rango (estadística o del asistente): baja 50–100, alta 100–250 y al menos
/// 20 mg/dL entre ambas. Son límites de la sugerencia, no objetivos médicos. Al aceptar, el valor se ajusta
/// además a lo editable en Ajustes (`ReferenceLines.clampedForSettings`).
enum RangeSuggestionBounds {
    static let low = 50...100
    static let high = 100...250
    static let minimumGap = 20

    static func isValid(low: Int, high: Int) -> Bool {
        Self.low.contains(low) && Self.high.contains(high) && low <= high - minimumGap
    }
}
