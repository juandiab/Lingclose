import SwiftUI

/// "Incluir consejos" (T-25): añade un consejo de bienestar por reglas a cada notificación y guarda la alerta para la
/// tarjeta "Qué hacer" de Hoy. Activado por defecto.
struct AlertTipsSection: View {
    @Bindable var alerts: AlertsController

    var body: some View {
        Section {
            Toggle(isOn: $alerts.settings.includeTips) {
                Label(String(localized: "alerts.tips.toggle", defaultValue: "Incluir consejos"), systemImage: "lightbulb")
            }
        } footer: {
            Text(String(localized: "alerts.tips.footer", defaultValue: "Añade a cada aviso un consejo de bienestar según el tipo de alerta, la hora y tu última comida o ejercicio del diario. Al tocar el aviso, Hoy muestra \"Qué hacer\". Se calcula en el teléfono, sin red."))
        }
    }
}
