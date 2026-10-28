import SwiftUI

/// Líneas de referencia de la curva y del tiempo en rango. Informativas; no son objetivos médicos.
/// "Sugerir rango" abre una hoja de revisión con una propuesta a partir de las lecturas propias (y, si hay
/// asistente configurado, de sus agregados); solo se aplica si el usuario la acepta.
struct ReferenceRangeSection: View {
    @AppStorage(ReferenceLines.lowKey) private var low = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var high = ReferenceLines.defaultHigh
    @Environment(\.rangeSuggester) private var rangeSuggester
    @State private var showingSuggestion = false

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
            Button(String(localized: "settings.range.suggest", defaultValue: "Sugerir rango"), systemImage: "wand.and.sparkles") {
                showingSuggestion = true
            }
            Button(String(localized: "settings.range.reset", defaultValue: "Restablecer \(ReferenceLines.defaultLow)–\(ReferenceLines.defaultHigh)"),
                   action: resetToDefaults)
            .disabled(low == ReferenceLines.defaultLow && high == ReferenceLines.defaultHigh)
        } header: {
            Text(String(localized: "settings.range", defaultValue: "Rango de referencia"))
        } footer: {
            Text(String(localized: "settings.range.footer", defaultValue: "Se usa en la curva, el sombreado de picos y el tiempo en rango. Solo orienta la lectura; no es un objetivo médico ni un dispositivo médico. \"Sugerir rango\" propone las líneas a partir de tus lecturas de los últimos 14 días y tú decides si usarlas."))
        }
        .onAppear(perform: clampStoredValues)
        .sheet(isPresented: $showingSuggestion) {
            RangeSuggestionSheet(suggester: rangeSuggester, currentLow: low, currentHigh: high, onAccept: apply)
        }
    }

    private func resetToDefaults() {
        low = ReferenceLines.defaultLow
        high = ReferenceLines.defaultHigh
    }

    /// Valores guardados fuera de lo editable (p. ej. de una versión anterior) se acotan al entrar.
    private func clampStoredValues() {
        let clamped = ReferenceLines.clampedForSettings(low: low, high: high)
        if clamped.low != low { low = clamped.low }
        if clamped.high != high { high = clamped.high }
    }

    /// Solo aquí cambia el rango: tras "Usar rango" en la hoja de revisión.
    private func apply(low newLow: Int, high newHigh: Int) {
        low = newLow
        high = newHigh
    }
}
