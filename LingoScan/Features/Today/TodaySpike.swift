import Foundation
import LingoCore

/// Pico sobre la línea de referencia alta, listo para dibujar: sombreado entre `start` y `end` y su índice bajo el pico.
struct TodaySpike: Sendable, Hashable, Identifiable {
    let start: Date
    let end: Date
    let peakAt: Date
    let peakValue: Int
    let index: Int

    var id: Date { start }

    init(_ spike: SpikeIndex.Spike) {
        start = spike.start.date
        end = spike.end.date
        peakAt = spike.peakAt.date
        peakValue = spike.peakValue
        index = spike.index
    }
}
