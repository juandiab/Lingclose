import Foundation

/// Un tramo de sueño de Apple Salud con su origen (identificador del paquete que lo escribió) (T-33).
struct SleepSegment: Sendable, Hashable {
    var start: Date
    var end: Date
    var stage: SleepStage
    var source: String
}
