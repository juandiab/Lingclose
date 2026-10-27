import Foundation
import Observation

/// Instante señalado con el dedo sobre la curva. Vive en un objeto aparte para que, al arrastrar,
/// solo se redibujen la lectura y el cursor, no las ~1 440 marcas de la curva.
@MainActor
@Observable
final class ChartSelection {
    var date: Date?
}
