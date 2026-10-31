/// Un dato con su rótulo (fila de "Datos del paciente", métrica, sensor). `isAvailable == false` es un dato que Apple
/// Salud no tiene o no dejó leer: el valor dice "No disponible en Apple Salud" y se atenúa.
struct MedicalFact: Sendable, Hashable {
    var label: String
    var value: String
    var isAvailable = true
}
