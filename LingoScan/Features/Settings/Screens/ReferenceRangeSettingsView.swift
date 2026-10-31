import SwiftUI

/// Ajustes › Lecturas › Rango de referencia: líneas baja y alta (informativas, no objetivos médicos), "Sugerir rango"
/// (hoja de revisión que solo se aplica si el usuario la acepta) y volver a los valores por defecto. También se llega
/// desde Alertas › Umbrales: se editan en un solo sitio.
struct ReferenceRangeSettingsView: View {
    @AppStorage(ReferenceLines.lowKey) private var low = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var high = ReferenceLines.defaultHigh
    @Environment(\.rangeSuggester) private var rangeSuggester
    @State private var showingSuggestion = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $low, in: ReferenceLines.lowRange, step: 5) {
                    StepperValueLabel(
                        title: String(localized: "settings.range.low", defaultValue: "Línea baja"),
                        value: String(localized: "settings.range.value", defaultValue: "\(low) mg/dL"))
                }
                Stepper(value: $high, in: ReferenceLines.highRange, step: 5) {
                    StepperValueLabel(
                        title: String(localized: "settings.range.high", defaultValue: "Línea alta"),
                        value: String(localized: "settings.range.value", defaultValue: "\(high) mg/dL"))
                }
            } header: {
                Text(String(localized: "settings.range.lines", defaultValue: "Líneas"))
            } footer: {
                Text(String(localized: "settings.range.footer", defaultValue: "Entre las dos líneas la curva se ve \"en rango\"; fuera de ellas avisan las alertas de alta y baja. Solo orientan la lectura: no son un objetivo médico."))
            }

            Section {
                Button(String(localized: "settings.range.suggest", defaultValue: "Sugerir rango"), systemImage: "wand.and.sparkles") {
                    showingSuggestion = true
                }
                if !isDefault {
                    Button(String(localized: "settings.range.reset", defaultValue: "Volver a \(ReferenceLines.defaultLow)–\(ReferenceLines.defaultHigh) mg/dL"),
                           systemImage: "arrow.uturn.backward", action: resetToDefaults)
                }
            } footer: {
                Text(String(localized: "settings.range.suggest.footer", defaultValue: "\"Sugerir rango\" propone las líneas a partir de tus lecturas de los últimos 14 días. Nada cambia hasta que pulses \"Usar rango\"."))
            }
        }
        .navigationTitle(String(localized: "settings.range", defaultValue: "Rango de referencia"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: clampStoredValues)
        .sheet(isPresented: $showingSuggestion) {
            RangeSuggestionSheet(suggester: rangeSuggester, currentLow: low, currentHigh: high, onAccept: apply)
        }
    }

    private var isDefault: Bool {
        low == ReferenceLines.defaultLow && high == ReferenceLines.defaultHigh
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

#Preview {
    NavigationStack {
        ReferenceRangeSettingsView()
    }
}
