import SwiftUI

/// Ajustes › Avanzado › Registro detallado: interruptor reservado para el registro de conexión de la Fase 3. Hoy solo
/// guarda la preferencia; la fila lo dice.
struct DiagnosticsRow: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Toggle(isOn: $viewModel.privateDiagnostics) {
            SettingsRowTitle(
                title: String(localized: "settings.diagnostics", defaultValue: "Registro detallado del sensor"),
                systemImage: "list.bullet.rectangle",
                detail: String(localized: "settings.diagnostics.footer", defaultValue: "Guardará en este iPhone más detalle de la conexión con el sensor para investigar fallos. Aún no registra nada más; nunca sale del dispositivo."))
        }
    }
}
