import Foundation
import LingoCore

extension AppEnvironment {
    /// Construye el exportador a Health sobre el almacén de la app. Quien lo use (Ajustes, T-12a) lo conserva.
    /// `policy` lo alimenta el modo "en pausa", `handover_at_utc` y "rellenar huecos".
    ///
    /// Además engancha el drenado automático (T-11b): `HealthDrainTrigger` observa la misma señal de lecturas nuevas
    /// que usa Hoy y drena este exportador con 30 s de debounce; `TodayView` lo avisa al volver a primer plano.
    /// `AppEnvironment.ui` llama a esta función una sola vez por proceso, así que hay un único trigger y un único exportador.
    func makeHealthExporter(policy: @escaping @Sendable () -> HealthExportPolicy = { .active }) -> HealthExporter {
        let exporter = HealthExporter(store: store, sink: HealthKitSink(), policy: policy)
        let trigger = HealthDrainTrigger(changes: todayData.changes()) { await exporter.drain() }
        trigger.install()
        return exporter
    }
}
