import Foundation

/// Por qué no se pudo construir la sugerencia. Un fallo de Salud o del asistente no es un error de aquí: la
/// sugerencia estadística sigue adelante y la hoja lo explica (`RangeSuggestion.healthNote`, `assistantNote`).
enum RangeSuggestionError: Error, Sendable, Equatable {
    case noReadings
    /// Horas con lecturas válidas en la ventana, frente a las 24 h mínimas.
    case insufficientCoverage(hours: Double, required: Double)
    case store(String)
}

extension RangeSuggestionError: LocalizedError, CustomStringConvertible {
    var description: String {
        switch self {
        case .noReadings:
            String(localized: "range.suggest.error.noReadings",
                   defaultValue: "No hay lecturas válidas de los últimos 14 días. La sugerencia sale de tus propios datos; vuelve a intentarlo cuando el sensor lleve al menos un día.")
        case .insufficientCoverage(let hours, let required):
            String(localized: "range.suggest.error.coverage",
                   defaultValue: "Solo hay \(hours.formatted(.number.precision(.fractionLength(1)))) h con lecturas válidas y hacen falta al menos \(Int(required)) h. Vuelve a intentarlo cuando el sensor lleve más tiempo.")
        case .store(let detail):
            String(localized: "range.suggest.error.store", defaultValue: "No se pudieron leer las lecturas guardadas (\(detail)).")
        }
    }

    var errorDescription: String? { description }
}
