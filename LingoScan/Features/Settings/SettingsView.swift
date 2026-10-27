import SwiftUI

/// Ajustes: unidad, alarmas, identidad de app, permisos, apariencia, diagnóstico privado y "Acerca de".
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    /// `nil` en previsualización (`PreviewData`): no hay credenciales reales.
    let identity: IdentityImportModel?
    /// `nil` mientras se crea el servicio de alarmas (arranque) y en previsualización.
    let alarms: AlarmSettingsModel?

    @Environment(\.openURL) private var openURL
    @Environment(\.mealAssistant) private var mealAssistant
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system

    var body: some View {
        NavigationStack {
            Form {
                unitSection
                alarmsSection
                mealAssistantSection
                ReferenceRangeSection()
                if let identity {
                    IdentitySection(model: identity)
                }
                permissionsSection
                appearanceSection
                diagnosticsSection
                aboutSection
            }
            .navigationTitle(String(localized: "settings.title", defaultValue: "Ajustes"))
            .task { await viewModel.refreshPermissions() }
        }
    }

    private var unitSection: some View {
        Section {
            LabeledContent(String(localized: "settings.unit", defaultValue: "Unidad de glucosa"), value: viewModel.glucoseUnit)
        } footer: {
            Text(String(localized: "settings.unit.footer", defaultValue: "Fija en mg/dL por ahora."))
        }
    }

    @ViewBuilder
    private var alarmsSection: some View {
        Section {
            if let alarms {
                NavigationLink {
                    AlarmsSettingsView(model: alarms)
                } label: {
                    Label(String(localized: "settings.alarms", defaultValue: "Alarmas"), systemImage: "bell")
                }
            } else {
                Label(String(localized: "settings.alarms.loading", defaultValue: "Alarmas (preparando…)"), systemImage: "bell")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(String(localized: "settings.alarms.footer", defaultValue: "Informativas; LingoScan no es un dispositivo médico."))
        }
    }

    private var mealAssistantSection: some View {
        Section {
            NavigationLink {
                LLMSettingsView(services: mealAssistant)
            } label: {
                Label(String(localized: "settings.mealAssistant", defaultValue: "Asistente de comidas"), systemImage: "sparkles")
            }
        } footer: {
            Text(String(localized: "settings.mealAssistant.footer", defaultValue: "Opcional: propone calorías y macros de una foto o descripción. Tú revisas y guardas."))
        }
    }

    private var permissionsSection: some View {
        Section {
            PermissionRow(title: String(localized: "settings.permission.bluetooth", defaultValue: "Bluetooth"), state: viewModel.bluetooth)
            PermissionRow(
                title: String(localized: "settings.permission.nfc", defaultValue: "NFC"),
                state: viewModel.nfcAvailable ? .granted : .unavailable)
            PermissionRow(
                title: String(localized: "settings.permission.health", defaultValue: "Apple Salud"),
                state: viewModel.healthAuthorized ? .granted : .notDetermined)
            Button(String(localized: "settings.permission.open", defaultValue: "Abrir Ajustes de iOS"), systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        } header: {
            Text(String(localized: "settings.permissions", defaultValue: "Permisos"))
        } footer: {
            Text(String(localized: "settings.permission.footer", defaultValue: "NFC \"disponible\" significa que este iPhone puede leer sensores. Apple Salud se pide desde Datos."))
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(String(localized: "settings.appearance", defaultValue: "Apariencia"), selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(String(localized: "settings.appearance", defaultValue: "Apariencia"))
        } footer: {
            Text(String(localized: "settings.appearance.footer", defaultValue: "Sistema sigue el modo claro u oscuro de iOS. El tamaño de texto siempre sigue el de iOS."))
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Toggle(String(localized: "settings.diagnostics", defaultValue: "Diagnóstico privado"), isOn: $viewModel.privateDiagnostics)
        } footer: {
            Text(String(localized: "settings.diagnostics.footer", defaultValue: "Solo guarda la preferencia en este iPhone. El registro detallado llega en la Fase 3; nada sale del dispositivo."))
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(String(localized: "settings.about.version", defaultValue: "Versión"), value: viewModel.about.version)
            LabeledContent(String(localized: "settings.about.build", defaultValue: "Compilación"), value: viewModel.about.build)
            LabeledContent(String(localized: "settings.about.fork", defaultValue: "Base del fork")) {
                Text(verbatim: viewModel.about.forkBaseCommit)
                    .font(.body.monospaced())
            }
        } header: {
            Text(String(localized: "settings.about", defaultValue: "Acerca de"))
        } footer: {
            Text(String(localized: "settings.about.footer", defaultValue: "LingoScan es un proyecto personal de bienestar, no un dispositivo médico."))
        }
    }
}
