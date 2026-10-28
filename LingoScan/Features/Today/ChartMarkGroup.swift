import CoreGraphics

/// Marcas de comida o ejercicio que caen tan cerca en pantalla que se dibujan como un solo botón.
struct ChartMarkGroup: Identifiable {
    /// En orden de hora; la primera da el icono y la hora del botón.
    let marks: [DiaryMark]
    /// Posición horizontal de la primera, en la capa visible.
    let x: CGFloat

    var id: String { marks.map(\.id).joined(separator: "|") }

    var first: DiaryMark { marks[0] }
}
