/// Líneas de referencia de la curva (mg/dL). No son objetivos médicos; solo orientan la lectura.
/// Se guardan en `AppStorage` con estas claves; Ajustes → "Rango de referencia" las edita.
enum ReferenceLines {
    static let lowKey = "today.referenceLow"
    static let highKey = "today.referenceHigh"
    static let defaultLow = 70
    static let defaultHigh = 140
    /// Valores permitidos en Ajustes. Los rangos no se solapan, así que `bajo < alto` siempre se cumple.
    static let lowRange = 40...100
    static let highRange = 120...250

    /// Ajusta un par al rango editable de Ajustes (p. ej. valores antiguos guardados fuera de él).
    static func clampedForSettings(low: Int, high: Int) -> (low: Int, high: Int) {
        (min(max(low, lowRange.lowerBound), lowRange.upperBound),
         min(max(high, highRange.lowerBound), highRange.upperBound))
    }

    /// Acota valores guardados: bajo ≥ 40, alto ≤ 400 y al menos 10 mg/dL de separación.
    static func normalized(low: Int, high: Int) -> (low: Int, high: Int) {
        let low = min(max(low, 40), 390)
        let high = min(max(high, low + 10), 400)
        return (low, high)
    }
}
