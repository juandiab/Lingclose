import Foundation
import LingoCore

/// Fuente de datos de Hoy. Un adaptador conectará `SQLiteStore` y el coordinador de sesión;
/// `PreviewData` implementa una versión sintética.
protocol TodayDataSource: Sendable {
    /// Lecturas de glucosa de cualquier elegibilidad dentro del rango; la vista filtra por `eligibility`.
    func readings(in range: ClosedRange<UTCInstant>) async throws -> [GlucoseReading]
    /// Lectura elegible más reciente, o `nil` si no hay ninguna.
    func latestEligibleReading() async throws -> GlucoseReading?
    /// Eventos del diario dentro del rango, para las marcas.
    func diaryEvents(in range: ClosedRange<UTCInstant>) async throws -> [DiaryEvent]
    /// Avisos de que hay datos nuevos. Termina cuando se cancela la tarea que lo consume.
    func changes() -> AsyncStream<Void>
    /// Diario donde escribe el registro rápido. `nil` en previsualización: Hoy usa entonces un diario en memoria.
    var diaryStore: (any DiaryStore)? { get }
}

extension TodayDataSource {
    var diaryStore: (any DiaryStore)? { nil }
}
