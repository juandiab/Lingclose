/// Por qué se rechaza una respuesta del modelo. Nunca se "arregla" inventando valores.
public enum FoodAnalysisParserError: Error, Sendable, Hashable {
    /// No hay JSON (ni directo ni entre ```json```).
    case noJSON
    case malformedJSON(String)
    case missingKind
    case unknownKind(String)
    /// Una etiqueta sin base legible no sirve: no se puede saber a qué cantidad se refieren los valores.
    case labelWithoutBasis
    case unknownBasis(String)
    /// Valor negativo, no finito o fuera de los límites de `NutrientLimits`.
    case valueOutOfRange(field: String, value: Double)
    /// El campo trae algo que no es número, `null` ni una cadena numérica.
    case notANumber(field: String)
}
