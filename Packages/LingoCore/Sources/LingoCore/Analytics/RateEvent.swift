/// Episodio de cambio rápido de la glucosa detectado por `RateOfChange.events(in:threshold:window:)`.
/// Informativo, no médico.
public struct RateEvent: Sendable, Hashable, Identifiable {
    public enum Direction: Sendable, Hashable {
        case rising
        case falling
    }

    /// Lectura donde empieza la excursión (mínimo de una subida o máximo de una bajada dentro del episodio).
    public let start: UTCInstant
    /// Lectura donde termina (máximo de una subida o mínimo de una bajada).
    public let end: UTCInstant
    public let direction: Direction
    /// Pendiente media del episodio en mg/dL por minuto: `(to − from) / minutos(end − start)`.
    /// Positiva al subir, negativa al bajar.
    public let slopePerMinute: Double
    /// Valor en `start` (mg/dL).
    public let from: Int
    /// Valor en `end` (mg/dL).
    public let to: Int

    public init(start: UTCInstant, end: UTCInstant, direction: Direction, slopePerMinute: Double, from: Int, to: Int) {
        self.start = start
        self.end = end
        self.direction = direction
        self.slopePerMinute = slopePerMinute
        self.from = from
        self.to = to
    }

    public var id: UTCInstant { start }

    /// Duración en segundos.
    public var duration: Int64 { end.epochSeconds - start.epochSeconds }
}
