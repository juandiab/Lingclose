import Foundation

/// Lectura **solo lectura** de la composición corporal de Apple Salud (T-33, adenda 1): peso, grasa corporal, masa
/// magra, IMC y cintura. La app usa `HealthKitBodyCompositionReader`; pruebas y previsualizaciones,
/// `PreviewBodyCompositionReader`. Nunca lanza: sin permiso o sin datos devuelve `.empty`.
protocol BodyCompositionReading: Sendable {
    /// Pide permiso de lectura de esas medidas (`toShare` vacío). Se llama al encender el interruptor del perfil.
    func requestAuthorization() async
    /// Valor más reciente de cada medida hasta `to` y tendencia dentro de `[from, to)`.
    func bodyComposition(from: Date, to: Date, timeZone: TimeZone) async -> BodyComposition
    /// Todas las muestras de cada medida dentro de `[from, to)` (T-34, reporte en PDF para el médico). Los lectores que
    /// no la implementan devuelven una serie vacía.
    func bodyMeasurementSeries(from: Date, to: Date) async -> BodyMeasurementSeries
}

extension BodyCompositionReading {
    func bodyMeasurementSeries(from: Date, to: Date) async -> BodyMeasurementSeries { .empty }
}
