import SwiftUI

/// Ajustes › Lecturas › Rango de referencia: muestra las líneas actuales y abre la pantalla donde se editan.
struct ReferenceRangeRow: View {
    @AppStorage(ReferenceLines.lowKey) private var low = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var high = ReferenceLines.defaultHigh

    var body: some View {
        let lines = ReferenceLines.normalized(low: low, high: high)
        NavigationLink(value: SettingsRoute.referenceRange) {
            LabeledContent {
                Text(String(localized: "range.suggest.pair", defaultValue: "\(lines.low)–\(lines.high) mg/dL"))
                    .monospacedDigit()
            } label: {
                SettingsRowTitle(title: String(localized: "settings.range", defaultValue: "Rango de referencia"),
                                 systemImage: "arrow.up.and.down")
            }
        }
    }
}
