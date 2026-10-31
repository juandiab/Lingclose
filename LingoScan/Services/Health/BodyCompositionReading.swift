import Foundation

/// Lectura **solo lectura** de la composición corporal de Apple Salud (T-33, adenda 1): peso, grasa corporal, masa
/// magra, IMC y cintura. La app usa `HealthKitBodyCompositionReader`; pruebas y previsualizaciones,
/// `PreviewBodyCompositionReader`. Nunca lanza: sin permiso o sin datos devuelve `.empty`.
protocol BodyCompositionReading: Sendable {
    /// Pide permiso de lectura de esas medidas (`toShare` vacío). Se llama al encender el interruptor del perfil.
    func requestAuthorization() async
    /// Valor más reciente de cada medida hasta `to` y tendencia dentro de `[from, to)`.
    func bodyComposition(from: Date, to: Date, timeZone: TimeZone) async -> BodyComposition
}
