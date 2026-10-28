import Foundation
import LingoCore

/// Lo que la hoja de revisión muestra: el rango propuesto, de dónde salió, la explicación, las cifras usadas y
/// el perfil de Salud. Nunca se aplica sola: el usuario la acepta o la descarta.
struct RangeSuggestion: Sendable, Equatable {
    enum Origin: Sendable, Equatable {
        /// Solo percentiles de las lecturas propias (sin asistente configurado o asistente fallido).
        case statistics
        /// Rango devuelto por el asistente a partir de los agregados.
        case assistant(provider: LLMProviderID, modelName: String)
    }

    /// Resumen de las lecturas propias usadas (ya agregadas).
    struct ReadingSummary: Sendable, Equatable {
        var count: Int
        var windowDays: Int
        var coverageHours: Double
        var first: Date?
        var last: Date?
        var percentile5: Double
        var percentile95: Double
        var median: Double
        var mean: Double
        var standardDeviation: Double
    }

    var low: Int
    var high: Int
    var explanation: String
    var origin: Origin
    var readings: ReadingSummary
    /// Propuesta estadística pura, para compararla cuando el asistente propuso otra cosa.
    var statisticalLow: Int
    var statisticalHigh: Int
    var profile: HealthProfile
    /// Salud no se pudo leer (sin permiso, no disponible): la sugerencia siguió sin perfil.
    var healthNote: String?
    /// El asistente estaba configurado pero falló: se muestra la estadística y el motivo.
    var assistantNote: String?

    var isAssistant: Bool {
        if case .assistant = origin { return true }
        return false
    }

    var differsFromStatistics: Bool { low != statisticalLow || high != statisticalHigh }
}
