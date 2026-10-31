import LingoCore
import SwiftUI

/// Pendiente de cambio rápido, plazo "sin datos" y silencio entre avisos.
struct AlertTimingSection: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            Stepper(value: $alerts.settings.rateThreshold, in: AlertSettings.rateThresholdRange, step: 0.5) {
                StepperValueLabel(title: String(localized: "alerts.rate", defaultValue: "Cambio rápido desde"),
                                  value: String(localized: "alerts.rate.value", defaultValue: "\(alerts.settings.rateThreshold.formatted(.number.precision(.fractionLength(1)))) mg/dL por minuto"))
            }
            Stepper(value: $alerts.settings.noDataAfterMinutes, in: AlertSettings.noDataRange, step: 5) {
                StepperValueLabel(title: String(localized: "alerts.noData.after", defaultValue: "Sin datos durante"),
                                  value: String(localized: "alerts.minutes", defaultValue: "\(alerts.settings.noDataAfterMinutes) min"))
            }
            Picker(String(localized: "alerts.cooldown", defaultValue: "Repetir el aviso cada"), selection: $alerts.settings.sharedCooldownMinutes) {
                ForEach(AlertSettings.cooldownChoices, id: \.self) { minutes in
                    Text(String(localized: "alerts.minutes", defaultValue: "\(minutes) min")).tag(minutes)
                }
            }
        } header: {
            Text(String(localized: "alerts.timing", defaultValue: "Cuándo avisar"))
        } footer: {
            Text(String(localized: "alerts.timing.footer", defaultValue: "Un cambio es rápido si la glucosa sube o baja más que esa cantidad cada minuto. Si la situación sigue, el aviso se repite con esa frecuencia; el de \"sin datos\", como mucho cada hora."))
        }
        .disabled(!alerts.settings.isEnabled)
    }
}
