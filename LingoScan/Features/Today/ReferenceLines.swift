/// Líneas de referencia de la curva (mg/dL). No son objetivos médicos; solo orientan la lectura.
/// Se guardan en `AppStorage` con estas claves; la pantalla de Ajustes podrá editarlas más adelante.
enum ReferenceLines {
    static let lowKey = "today.referenceLow"
    static let highKey = "today.referenceHigh"
    static let defaultLow = 70
    static let defaultHigh = 140

    /// Acota valores guardados: bajo ≥ 40, alto ≤ 400 y al menos 10 mg/dL de separación.
    static func normalized(low: Int, high: Int) -> (low: Int, high: Int) {
        let low = min(max(low, 40), 390)
        let high = min(max(high, low + 10), 400)
        return (low, high)
    }
}
