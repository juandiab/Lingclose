import SwiftUI

/// Ajustes → Alertas: interruptor general y enlace a la configuración detallada. Informativas, no médicas.
struct AlertsSection: View {
    @Environment(\.alerts) private var alerts

    var body: some View {
        if let alerts {
            AlertsSectionContent(alerts: alerts)
        } else {
            Section {
                Label(String(localized: "alerts.unavailable", defaultValue: "Alertas no disponibles en la vista previa"), systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "alerts.header", defaultValue: "Alertas"))
            }
        }
    }
}
