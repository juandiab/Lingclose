import Foundation
import LingoCore

/// Marca de comida o ejercicio sobre la curva, con el detalle que muestra su popover.
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
    /// Gramos o duración ya formateados.
    let detail: String?
    let text: String?
    let synthetic: Bool
    /// Duración del ejercicio en minutos (fin = `date + duración`); `nil` en comidas o sin duración.
    let durationMinutes: Int?

    /// Fin del ejercicio si tiene duración.
    var endDate: Date? { durationMinutes.map { date.addingTimeInterval(Double($0) * 60) } }

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
        detail = event.detailText
        text = event.text
        synthetic = event.synthetic
        durationMinutes = event.durationMin
    }
}
