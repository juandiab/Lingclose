/// Errores tipados del almacén.
public enum StoreError: Error, Sendable, Hashable {
    /// La base fue escrita por una versión más nueva de la app.
    case schemaTooNew(found: Int, supported: Int)
    case migrationFailed(version: Int, reached: Int)
    case unknownSession(sessionID: String)
    /// Criterio del ajuste de Astra (T-07/T-09/T-10): una lectura real no puede pertenecer a una sesión sintética.
    case realReadingInSyntheticSession(recordID: String, sessionID: String)
    /// Una sesión sintética nunca pasa a real (contrato §5.1, C6).
    case syntheticSessionCannotBecomeReal(sessionID: String)
    case recordIDMismatch(recordID: String, expected: String)
    case lifeCountOutOfRange(Int)
    case unknownReading(recordID: String)
    case corruptRow(table: String, detail: String)
    /// Registro de nutrición incoherente con su evento o con las reglas de T-21 (`meal_nutrition`).
    case invalidMealNutrition(eventID: String, reason: String)
}
