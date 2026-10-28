import SwiftUI

/// Contenedor raíz con las cinco pestañas principales.
struct RootTabView: View {
    @State private var todayViewModel: TodayViewModel
    @State private var sensorViewModel: SensorViewModel
    @State private var ui: AppUIModels
    @State private var selection = AppTab.today
    private let identityImport: IdentityImportModel?
    private let mealAssistant: MealAssistantServices
    private let rangeSuggester: any RangeSuggesting
    private let workoutImport: WorkoutImportTrigger?
    private let alerts: AlertsController?
    @Environment(\.scenePhase) private var scenePhase

    /// Fuentes reales: `SQLiteStore` y `SensorSessionCoordinator`.
    init(environment: AppEnvironment) {
        _todayViewModel = State(initialValue: TodayViewModel(
            dataSource: environment.todayData, sensorSource: environment.sensorStatus
        ))
        _sensorViewModel = State(initialValue: SensorViewModel(
            statusSource: environment.sensorStatus, actions: environment.sensorActions
        ))
        _ui = State(initialValue: environment.ui)
        identityImport = environment.identityImport
        let assistant = MealAssistantServices.live(store: environment.store)
        mealAssistant = assistant
        rangeSuggester = RangeSuggestionService.live(readings: environment.store, assistant: assistant)
        workoutImport = environment.workoutImport
        alerts = environment.alerts
    }

    /// `PreviewData` (sintético y señalado como tal): `#Preview` y `-previewSensorState`.
    init(previewState: SensorPresentationState) {
        let data = PreviewData(sensorState: previewState)
        _todayViewModel = State(initialValue: TodayViewModel(dataSource: data, sensorSource: data))
        _sensorViewModel = State(initialValue: SensorViewModel(statusSource: data, actions: PreviewSensorActions()))
        _ui = State(initialValue: .preview(events: data.events))
        identityImport = nil
        mealAssistant = .preview
        rangeSuggester = PreviewRangeSuggester()
        workoutImport = nil
        alerts = nil
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(String(localized: "tab.today", defaultValue: "Hoy"), systemImage: "drop.fill", value: AppTab.today) {
                TodayView(viewModel: todayViewModel, sensorViewModel: sensorViewModel)
            }
            Tab(String(localized: "tab.diary", defaultValue: "Diario"), systemImage: "book.closed", value: AppTab.diary) {
                DiaryView(viewModel: ui.diary)
            }
            Tab(String(localized: "tab.reports", defaultValue: "Reportes"), systemImage: "chart.xyaxis.line", value: AppTab.reports) {
                ReportsView()
            }
            Tab(String(localized: "tab.data", defaultValue: "Datos"), systemImage: "externaldrive", value: AppTab.data) {
                DataView(viewModel: ui.data)
            }
            Tab(String(localized: "tab.settings", defaultValue: "Ajustes"), systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(viewModel: ui.settings, identity: identityImport)
            }
        }
        .environment(\.tabSelector, TabSelector { selection = $0 })
        .environment(\.mealAssistant, mealAssistant)
        .environment(\.rangeSuggester, rangeSuggester)
        .environment(\.workoutImport, workoutImport)
        .environment(\.alerts, alerts)
        .onReceive(NotificationCenter.default.publisher(for: AlertNotificationDelegate.openToday)) { _ in
            selection = .today
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { alerts?.sceneDidBecomeActive() }
        }
        .modifier(IdentityImportAlert(model: identityImport))
    }
}

#Preview {
    RootTabView(previewState: .streaming)
}
