/// Lo que una página dibuja de una pieza del flujo (T-34): el bloque entero o un tramo de filas de una tabla.
struct MedicalPageSlice: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case block
        /// Filas `rows` de la tabla; `isContinuation` si no es el primer tramo (el título dice "continuación").
        case rows(rows: Range<Int>, isContinuation: Bool)
    }

    var id: String
    var kind: Kind
    var height: Double
}
