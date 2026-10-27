import Foundation
import LingoCore

/// Marca de comida o ejercicio sobre la curva.
struct DiaryMark: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        case meal
        case exercise

        var systemImage: String {
            switch self {
            case .meal: "fork.knife"
            case .exercise: "figure.run"
            }
        }

        var title: String {
            switch self {
            case .meal: String(localized: "today.mark.meal", defaultValue: "Comida")
            case .exercise: String(localized: "today.mark.exercise", defaultValue: "Ejercicio")
            }
        }
    }

    let id: String
    let kind: Kind
    let date: Date

    /// Solo comidas y ejercicio, y no las borradas; las notas no se marcan en la curva.
    init?(_ event: DiaryEvent) {
        guard !event.deleted else { return nil }
        switch event.kind {
        case .meal: kind = .meal
        case .exercise: kind = .exercise
        case .note, .sensorNote: return nil
        }
        id = event.eventID
        date = event.at.date
    }
}
