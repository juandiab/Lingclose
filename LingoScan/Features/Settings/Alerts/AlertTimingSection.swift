import LingoCore
import SwiftUI

/// Pendiente de cambio rápido, plazo "sin datos" y silencio entre avisos.
struct AlertTimingSection: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            Stepper(value: $alerts.settings.rateThreshold, in: AlertSettings.rateThresholdRange, step: 0.5) {
                LabeledContent(String(localized: "alerts.rate", defaultValue: "Cambio rápido"),
                               value: String(localized: "alerts.rate.value", defaultValue: "\(alerts.settings.rateThreshold.formatted(.number.precision(.fractionLength(1)))) mg/dL/min"))
            }
            Stepper(value: $alerts.settings.noDataAfterMinutes, in: AlertSettings.noDataRange, step: 5) {
                LabeledContent(String(localized: "alerts.noData.after", defaultValue: "Sin datos tras"),
                               value: String(localized: "alerts.minutes", defaultValue: "\(alerts.settings.noDataAfterMinutes) min"))
            }
            Picker(String(localized: "alerts.cooldown", defaultValue: "Silencio entre avisos"), selection: $alerts.settings.sharedCooldownMinutes) {
                ForEach(AlertSettings.cooldownChoices, id: \.self) { minutes in
                    Text(String(localized: "alerts.minutes", defaultValue: "\(minutes) min")).tag(minutes)
                }
            }
        } header: {
            Text(String(localized: "alerts.timing", defaultValue: "Sensibilidad"))
        } footer: {
            Text(String(localized: "alerts.timing.footer", defaultValue: "Cambio rápido compara la media de los 5 primeros y los 5 últimos minutos de una ventana de 15. Mientras una condición se mantiene, el aviso se repite tras el silencio elegido; \"sin datos\" se repite como mucho cada hora."))
        }
        .disabled(!alerts.settings.isEnabled)
    }
}
