import Foundation
import LingoCore

/// Reglas puras de "Sugerir rango": ventana, cobertura mínima y propuesta estadística (percentiles 5 y 95
/// redondeados a múltiplos de 5 y acotados por `RangeSuggestionBounds`). Sin red ni Salud.
enum RangeSuggestionPolicy {
    static let windowDays = 14
    static let minimumCoverageHours = 24.0
    static let lowPercentile = 5.0
    static let highPercentile = 95.0
    static let step = 5

    /// Ventana de lectura: los últimos `windowDays` días hasta `now`.
    static func window(endingAt now: Date) -> ClosedRange<UTCInstant> {
        UTCInstant(now.addingTimeInterval(-Double(windowDays) * 86_400))...UTCInstant(now)
    }

    /// Propuesta estadística: p5 → línea baja, p95 → línea alta, cada una al múltiplo de 5 más cercano y dentro
    /// de sus límites; si quedan a menos de 20 mg/dL, se sube la alta (y, si no cabe, se baja la baja).
    static func statisticalProposal(percentile5: Double, percentile95: Double) -> (low: Int, high: Int) {
        var low = clamp(roundToStep(percentile5), to: RangeSuggestionBounds.low)
        var high = clamp(roundToStep(percentile95), to: RangeSuggestionBounds.high)
        if high - low < RangeSuggestionBounds.minimumGap {
            high = clamp(low + RangeSuggestionBounds.minimumGap, to: RangeSuggestionBounds.high)
        }
        if high - low < RangeSuggestionBounds.minimumGap {
            low = clamp(high - RangeSuggestionBounds.minimumGap, to: RangeSuggestionBounds.low)
        }
        return (low, high)
    }

    static func roundToStep(_ value: Double) -> Int {
        Int((value / Double(step)).rounded()) * step
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
