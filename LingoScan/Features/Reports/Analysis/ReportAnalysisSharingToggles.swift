import SwiftUI

/// Los tres interruptores del contexto opcional (T-33), con una línea de explicación cada uno. Los usan la hoja de
/// análisis ("Qué se enviará") y Ajustes › Asistente con IA, los dos sobre el mismo `LLMSettingsStore`.
/// Quien lo usa reacciona a los cambios con `onChange(of:)` (guardar, pedir permiso de Salud, recalcular).
struct ReportAnalysisSharingToggles: View {
    @Binding var sharing: ReportAnalysisSharing

    var body: some View {
        ForEach(ReportAnalysisSharingOption.allCases) { option in
            Toggle(isOn: $sharing[option]) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Text(option.title)
                        .foregroundStyle(Tokens.Studio.textPrimary)
                    Text(option.explanation)
                        .font(.footnote)
                        .foregroundStyle(Tokens.Studio.textSecondary)
                }
            }
        }
    }
}
