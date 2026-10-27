import Foundation
import LingoCore

extension AppEnvironment {
    /// Construye el exportador a Health sobre el almacén de la app. Quien lo use (Ajustes, T-12a) lo conserva.
    /// `policy` lo alimenta el modo "en pausa", `handover_at_utc` y "rellenar huecos".
    func makeHealthExporter(policy: @escaping @Sendable () -> HealthExportPolicy = { .active }) -> HealthExporter {
        HealthExporter(store: store, sink: HealthKitSink(), policy: policy)
    }
}
