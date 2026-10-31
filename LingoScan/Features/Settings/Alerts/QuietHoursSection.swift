import SwiftUI

/// Horas de silencio (hora local) y si la baja las ignora.
struct QuietHoursSection: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            Toggle(String(localized: "alerts.quiet.toggle", defaultValue: "Silenciar en un horario"), isOn: $alerts.settings.quietHoursEnabled)
            if alerts.settings.quietHoursEnabled {
                DatePicker(String(localized: "alerts.quiet.start", defaultValue: "Desde"),
                           selection: $alerts.settings.quietStart, displayedComponents: .hourAndMinute)
                DatePicker(String(localized: "alerts.quiet.end", defaultValue: "Hasta"),
                           selection: $alerts.settings.quietEnd, displayedComponents: .hourAndMinute)
            }
            Toggle(String(localized: "alerts.quiet.lowOverrides", defaultValue: "Avisar de glucosa baja igualmente"),
                   isOn: $alerts.settings.lowOverridesQuietHours)
        } header: {
            Text(String(localized: "alerts.quiet", defaultValue: "Horas de silencio"))
        } footer: {
            Text(String(localized: "alerts.quiet.footer", defaultValue: "En esas horas no llegan avisos; si la condición sigue al terminar, se avisa entonces."))
        }
        .disabled(!alerts.settings.isEnabled)
    }
}
