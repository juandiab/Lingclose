import Foundation
import SwiftUI

/// Trozo de un tramo con un solo color: sobre la referencia alta (rojo), en el rango (neutro) o bajo la
/// baja (azul). Los cruces con una referencia se interpolan en el tiempo y el vértice de cruce pertenece
/// a los dos trozos, así la línea no se corta. No depende de la geometría del chart: un degradado se
/// aplica sobre un rectángulo que Swift Charts elige de forma distinta en una gráfica desplazable.
struct GlucoseColorRun: Identifiable, Hashable {
    enum Band: Hashable {
        case low, inRange, high
    }

    struct Vertex: Hashable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let id: String
    let band: Band
    let vertices: [Vertex]

    var color: Color {
        switch band {
        case .high: Tokens.Palette.high
        case .low: Tokens.Palette.low
        case .inRange: .primary
        }
    }

    static func band(of value: Double, low: Int, high: Int) -> Band {
        if value > Double(high) { return .high }
        if value < Double(low) { return .low }
        return .inRange
    }

    /// Parte `segment` en trozos de un color. Un valor exactamente en una referencia cuenta como en rango;
    /// el cambio de color se hace en ese mismo punto.
    static func runs(for segment: GlucoseSegment, low: Int, high: Int) -> [GlucoseColorRun] {
        guard let first = segment.points.first else { return [] }
        var result: [GlucoseColorRun] = []
        var band = band(of: Double(first.value), low: low, high: high)
        var current = [Vertex(date: first.date, value: Double(first.value))]

        func close() {
            result.append(GlucoseColorRun(id: "\(segment.id)-\(result.count)", band: band, vertices: current))
        }

        for (previous, next) in zip(segment.points, segment.points.dropFirst()) {
            let a = Double(previous.value)
            let b = Double(next.value)
            // Referencias estrictamente entre ambos valores, en el orden en que se cruzan.
            let crossed = [Double(low), Double(high)]
                .filter { (a < $0 && $0 < b) || (b < $0 && $0 < a) }
                .sorted { abs($0 - a) < abs($1 - a) }
            for threshold in crossed {
                let fraction = (threshold - a) / (b - a)
                let date = previous.date.addingTimeInterval(fraction * next.date.timeIntervalSince(previous.date))
                let vertex = Vertex(date: date, value: threshold)
                current.append(vertex)
                close()
                band = Self.band(of: threshold + (b > a ? 0.5 : -0.5), low: low, high: high)
                current = [vertex]
            }
            let nextBand = Self.band(of: b, low: low, high: high)
            if nextBand != band, let last = current.last {
                // El punto anterior estaba justo en una referencia: el color cambia ahí.
                close()
                band = nextBand
                current = [last]
            }
            current.append(Vertex(date: next.date, value: b))
        }
        close()
        return result
    }
}
