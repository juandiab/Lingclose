import SwiftUI

/// "Analizar con IA": vidrio teñido con `sparkles`. Solo aparece si el entorno trae `reportAnalysisEntry`.
struct ReportAnalyzeButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "reports.analyze", defaultValue: "Analizar con IA"), systemImage: "sparkles")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(.capsule)
                .studioGlass(Capsule(), tint: Tokens.Studio.accent, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

#Preview {
    ReportAnalyzeButton(isEnabled: true) {}
        .padding()
}
