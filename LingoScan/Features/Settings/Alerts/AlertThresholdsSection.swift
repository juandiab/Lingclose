import SwiftUI

/// Alta y baja leídas del rango de referencia (no se duplican); se editan en su sección.
struct AlertThresholdsSection: View {
    @AppStorage(ReferenceLines.lowKey) private var low = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var high = ReferenceLines.defaultHigh

    var body: some View {
        let lines = ReferenceLines.normalized(low: low, high: high)
        Section {
            LabeledContent(String(localized: "alerts.threshold.high", defaultValue: "Alta por encima de"),
                           value: String(localized: "alerts.mgdl", defaultValue: "\(lines.high) mg/dL"))
            LabeledContent(String(localized: "alerts.threshold.low", defaultValue: "Baja por debajo de"),
                           value: String(localized: "alerts.mgdl", defaultValue: "\(lines.low) mg/dL"))
            NavigationLink {
                Form { ReferenceRangeSection() }
                    .navigationTitle(String(localized: "settings.range", defaultValue: "Rango de referencia"))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Text(String(localized: "alerts.threshold.edit", defaultValue: "Cambiar en Rango de referencia"))
            }
        } header: {
            Text(String(localized: "alerts.thresholds", defaultValue: "Umbrales"))
        } footer: {
            Text(String(localized: "alerts.thresholds.footer", defaultValue: "Son las líneas del rango de referencia; se editan en un solo sitio."))
        }
    }
}
