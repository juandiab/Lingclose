import LingoCore

extension DiaryEventKind {
    /// Tipos que el usuario puede crear; `sensorNote` solo llega por importación.
    static let creatable: [DiaryEventKind] = [.meal, .exercise, .note]

    var title: String {
        switch self {
        case .meal: String(localized: "diary.kind.meal", defaultValue: "Comida")
        case .exercise: String(localized: "diary.kind.exercise", defaultValue: "Ejercicio")
        case .note: String(localized: "diary.kind.note", defaultValue: "Nota")
        case .sensorNote: String(localized: "diary.kind.sensorNote", defaultValue: "Nota del sensor")
        }
    }

    var systemImage: String {
        switch self {
        case .meal: "fork.knife"
        case .exercise: "figure.run"
        case .note: "note.text"
        case .sensorNote: "sensor"
        }
    }
}
