import SwiftUI

/// Ajustes › Lecturas › Unidad de glucosa: informativa, fija en mg/dL por ahora (D-12); lo dice en la propia fila.
struct UnitRow: View {
    let unit: String

    var body: some View {
        LabeledContent {
            Text(unit)
        } label: {
            SettingsRowTitle(
                title: String(localized: "settings.unit", defaultValue: "Unidad de glucosa"),
                systemImage: "drop",
                detail: String(localized: "settings.unit.footer", defaultValue: "Por ahora solo mg/dL."))
        }
    }
}
