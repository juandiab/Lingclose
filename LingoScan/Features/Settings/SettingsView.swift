import SwiftUI

/// Ajustes, agrupados por lo que importa al usuario (T-31, D-34): Lecturas, Personalización, Conexiones, Avanzado y
/// Acerca de (`SettingsGroup`). Cada grupo tiene un header corto y un pie en lenguaje llano; lo que necesita más filas
/// vive en una subpantalla con `NavigationLink`.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    /// `nil` en previsualización (`PreviewData`): no hay credenciales reales.
    let identity: IdentityImportModel?

    @Environment(\.mealAssistant) private var mealAssistant
    @Environment(\.alerts) private var alerts

    var body: some View {
        NavigationStack {
            Form {
                ForEach(SettingsGroup.allCases) { group in
                    Section {
                        rows(for: group)
                    } header: {
                        Text(group.title)
                    } footer: {
                        Text(group.footer)
                    }
                }
            }
            .navigationTitle(String(localized: "settings.title", defaultValue: "Ajustes"))
            .navigationDestination(for: SettingsRoute.self, destination: destination)
            .appBackground()
            .task { await viewModel.refreshPermissions() }
        }
    }

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .referenceRange:
            ReferenceRangeSettingsView()
        case .alerts:
            if let alerts { AlertsSettingsView(alerts: alerts) }
        case .health:
            HealthSettingsView(isAuthorized: viewModel.healthAuthorized)
        case .assistant:
            LLMSettingsView(services: mealAssistant)
        case .identity:
            SensorIdentityView(model: identity)
        case .permissions:
            PermissionsSettingsView(viewModel: viewModel)
        case .technicalInfo:
            TechnicalInfoView(about: viewModel.about)
        }
    }

    @ViewBuilder
    private func rows(for group: SettingsGroup) -> some View {
        switch group {
        case .readings:
            UnitRow(unit: viewModel.glucoseUnit)
            ReferenceRangeRow()
            AlertsRow()
        case .personalization:
            LanguageRow()
            AppearanceRow()
            BackgroundStyleRow()
        case .medicalReport:
            MedicalReportNameRow()
        case .connections:
            HealthRow(isAuthorized: viewModel.healthAuthorized)
            AssistantRow(services: mealAssistant)
        case .advanced:
            IdentityRow(model: identity)
            PermissionsRow(viewModel: viewModel)
            DiagnosticsRow(viewModel: viewModel)
        case .about:
            AboutRows(about: viewModel.about)
        }
    }
}
