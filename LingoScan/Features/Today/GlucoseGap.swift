import Foundation

/// Intervalo sin lecturas válidas entre dos tramos (desconexión, calentamiento o lecturas con bandera de calidad).
struct GlucoseGap: Sendable, Hashable, Identifiable {
    let start: Date
    let end: Date

    var id: Date { start }

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
