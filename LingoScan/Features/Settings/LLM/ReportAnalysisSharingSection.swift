import SwiftUI

/// Ajustes › Asistente con IA › "Qué puede ver la IA en los reportes" (T-33): los mismos tres interruptores que la hoja
/// de análisis, sobre el mismo `LLMSettingsStore`. Encender uno de Salud pide su permiso de lectura en ese momento.
struct ReportAnalysisSharingSection: View {
    let settings: LLMSettingsStore
    @State private var sharing: ReportAnalysisSharing
    @Environment(\.reportAnalysisHealth) private var health

    init(settings: LLMSettingsStore) {
        self.settings = settings
        _sharing = State(initialValue: settings.analysisSharing())
    }

    var body: some View {
        Section {
            ReportAnalysisSharingToggles(sharing: $sharing)
        } header: {
            Text(String(localized: "llm.analysisSharing.header", defaultValue: "Qué puede ver la IA en los reportes"))
        } footer: {
            Text(ReportAnalysisSharingOption.commonFooter)
        }
        .onChange(of: sharing) { old, new in
            save(from: old, to: new)
        }
    }

    /// Guarda lo que cambió y, si se encendió uno de Salud, pide su permiso de lectura.
    private func save(from old: ReportAnalysisSharing, to new: ReportAnalysisSharing) {
        let turnedOn = ReportAnalysisSharingOption.allCases.filter { old[$0] != new[$0] && new[$0] }
        for option in ReportAnalysisSharingOption.allCases where old[option] != new[option] {
            settings.setAnalysisSharing(option, isOn: new[option])
        }
        let health = health
        for option in turnedOn where option.readsHealth {
            Task { await health.requestAccess(for: option) }
        }
    }
}
