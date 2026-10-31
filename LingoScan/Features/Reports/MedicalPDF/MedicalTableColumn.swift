/// Columna de una `MedicalTable`: título, peso relativo del ancho y alineación.
struct MedicalTableColumn: Sendable, Hashable {
    var title: String
    var weight: Double
    var alignment: MedicalColumnAlignment = .trailing
}
