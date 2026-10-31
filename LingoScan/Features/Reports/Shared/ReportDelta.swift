import SwiftUI

/// Cambio entre dos semanas: texto, sentido de la flecha y si es mejora (sin juicio médico: solo el sentido del dato).
struct ReportDelta: Hashable {
    enum Direction: Hashable {
        case up, down, flat
    }

    enum Judgment: Hashable {
        case better, worse, neutral
    }

    let text: String
    let direction: Direction
    let judgment: Judgment

    var systemImage: String {
        switch direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    var color: Color {
        switch judgment {
        case .better: ReportPalette.better
        case .worse: ReportPalette.worse
        case .neutral: .secondary
        }
    }

    var spokenJudgment: String {
        switch judgment {
        case .better: String(localized: "reports.delta.better", defaultValue: "mejor que la semana anterior")
        case .worse: String(localized: "reports.delta.worse", defaultValue: "peor que la semana anterior")
        case .neutral: String(localized: "reports.delta.neutral", defaultValue: "sin valoración")
        }
    }

    /// Sentido según el valor y un umbral bajo el que se considera estable.
    static func direction(_ value: Double, threshold: Double) -> Direction {
        if value >= threshold { return .up }
        if value <= -threshold { return .down }
        return .flat
    }
}
