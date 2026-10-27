import Foundation
import LingoCore

/// Formulario de alta o edición. Los números se guardan como texto para no perder lo que el usuario teclea.
struct DiaryDraft: Equatable {
    var kind: DiaryEventKind = .meal
    var at: Date
    var text = ""
    var carbsText = ""
    var durationText = ""

    /// Alta: tipo comida, hora de ahora.
    init(now: Date) {
        at = now
    }

    /// Edición: parte del evento actual.
    init(event: DiaryEvent) {
        kind = event.kind
        at = event.at.date
        text = event.text ?? ""
        carbsText = event.carbsG.map { Self.numberText($0) } ?? ""
        durationText = event.durationMin.map(String.init) ?? ""
    }

    static let carbsRange = 0.0...1_000.0
    static let durationRange = 1...1_440

    var carbsG: Double? {
        guard kind == .meal else { return nil }
        return Self.parse(carbsText)
    }

    var durationMin: Int? {
        guard kind == .exercise else { return nil }
        return Int(durationText.trimmingCharacters(in: .whitespaces))
    }

    var trimmedText: String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    enum Problem: Equatable {
        case carbsOutOfRange
        case durationMissing
        case noteIsEmpty
    }

    /// Primer problema que impide guardar, o `nil`. Gramos y texto de la comida son opcionales.
    var problem: Problem? {
        switch kind {
        case .meal:
            if !carbsText.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let g = carbsG, Self.carbsRange.contains(g) else { return .carbsOutOfRange }
            }
            return nil
        case .exercise:
            guard let m = durationMin, Self.durationRange.contains(m) else { return .durationMissing }
            return nil
        case .note, .sensorNote:
            return trimmedText == nil ? .noteIsEmpty : nil
        }
    }

    var isValid: Bool { problem == nil }

    /// Admite coma o punto decimal.
    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let value = Double(t), value.isFinite else { return nil }
        return value
    }

    private static func numberText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
