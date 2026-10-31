/// Fila de la barra de tiempo en rangos: tramo, texto del rango en la unidad del reporte, porcentaje y tiempo por día.
struct MedicalRangeRow: Sendable, Hashable {
    var band: MedicalRangeBand
    var name: String
    var rangeText: String
    var fraction: Double
    var percentText: String
    var perDayText: String
}
