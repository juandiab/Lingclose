import LingoCore
import SwiftUI

/// Un interruptor por tipo de alerta.
struct AlertKindsSection: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            ForEach(AlertKind.allCases) { kind in
                Toggle(isOn: $alerts.settings[enabled: kind]) {
                    Label(kind.settingsTitle, systemImage: kind.systemImage)
                }
            }
        } header: {
            Text(String(localized: "alerts.kinds", defaultValue: "Tipos"))
        } footer: {
            Text(String(localized: "alerts.kinds.footer", defaultValue: "Baja y bajada rápida llegan como avisos urgentes y pueden atravesar un modo de concentración."))
        }
        .disabled(!alerts.settings.isEnabled)
    }
}
