import Foundation

/// Fuente del estado del sensor para la UI. Un adaptador conectará `SensorSessionCoordinator` (T-08);
/// `PreviewData` implementa una versión sintética.
protocol SensorStatusSource: Sendable {
    /// Estado actual.
    func currentStatus() async -> SensorStatusSnapshot
    /// Cambios posteriores de estado. Termina cuando se cancela la tarea que lo consume.
    func statusUpdates() -> AsyncStream<SensorStatusSnapshot>
}
