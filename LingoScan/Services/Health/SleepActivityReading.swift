import Foundation

/// Lectura **solo lectura** de sueño y pasos de Apple Salud para el análisis de reportes (T-33). La app usa
/// `HealthKitSleepActivityReader`; pruebas y previsualizaciones, `PreviewSleepActivityReader`. Nunca lanza: sin
/// permiso, sin Salud o sin datos devuelve listas vacías y el análisis sigue sin ese bloque.
protocol SleepActivityReading: Sendable {
    /// Pide permiso de lectura de sueño y pasos (`toShare` vacío). Se llama al encender el interruptor.
    func requestAuthorization() async
    /// Noches cuya sesión principal empieza en `[from, to)`, agrupadas con `SleepNightGrouper`.
    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async -> [SleepNight]
    /// Pasos por día local en `[from, to)`.
    func dailySteps(from: Date, to: Date, timeZone: TimeZone) async -> [DailySteps]
}
