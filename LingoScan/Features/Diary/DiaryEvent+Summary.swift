import Foundation
import LingoCore

extension DiaryEvent {
    /// Gramos o duración, si el evento los tiene ("45 g", "30 min").
    var detailText: String? {
        switch kind {
        case .meal:
            carbsG.map { String(localized: "diary.carbs.value", defaultValue: "\($0.formatted(.number.precision(.fractionLength(0...1)))) g de carbohidratos") }
        case .exercise:
            durationMin.map { String(localized: "diary.duration.value", defaultValue: "\($0) min") }
        case .note, .sensorNote:
            nil
        }
    }

    /// Una frase para VoiceOver: tipo, detalle, texto y hora.
    var spokenSummary: String {
        [kind.title, detailText, text, at.date.formatted(date: .omitted, time: .shortened)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
