import SwiftUI

/// Líneas de referencia de la curva y del tiempo en rango. Informativas; no son objetivos médicos.
struct ReferenceRangeSection: View {
    @AppStorage(ReferenceLines.lowKey) private var low = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var high = ReferenceLines.defaultHigh

    var body: some View {
        Section {
            Stepper(value: $low, in: ReferenceLines.lowRange, step: 5) {
                LabeledContent(
                    String(localized: "settings.range.low", defaultValue: "Línea baja"),
                    value: String(localized: "settings.range.value", defaultValue: "\(low) mg/dL"))
            }
            Stepper(value: $high, in: ReferenceLines.highRange, step: 5) {
                LabeledContent(
                    String(localized: "settings.range.high", defaultValue: "Línea alta"),
                    value: String(localized: "settings.range.value", defaultValue: "\(high) mg/dL"))
            }
            Button(String(localized: "settings.range.reset", defaultValue: "Restablecer \(ReferenceLines.defaultLow)–\(ReferenceLines.defaultHigh)")) {
                low = ReferenceLines.defaultLow
                high = ReferenceLines.defaultHigh
            }
            .disabled(low == ReferenceLines.defaultLow && high == ReferenceLines.defaultHigh)
        } header: {
            Text(String(localized: "settings.range", defaultValue: "Rango de referencia"))
        } footer: {
            Text(String(localized: "settings.range.footer", defaultValue: "Se usa en la curva, el sombreado de picos y el tiempo en rango. Solo orienta la lectura; no es un objetivo médico ni un dispositivo médico."))
        }
        .onAppear {
            let clamped = ReferenceLines.clampedForSettings(low: low, high: high)
            if clamped.low != low { low = clamped.low }
            if clamped.high != high { high = clamped.high }
        }
    }
}
