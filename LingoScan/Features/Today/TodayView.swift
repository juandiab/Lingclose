import SwiftUI

/// Pantalla Hoy: navegación por día, valor actual, curva 6 h / 12 h / 24 h con picos, marcas y arrastre,
/// fila de registro y "+" para anotar en dos toques.
struct TodayView: View {
    @Bindable var viewModel: TodayViewModel
    let sensorViewModel: SensorViewModel

    @AppStorage(TodayPeriod.storageKey) private var storedHours = TodayPeriod.sixHours.rawValue
    @AppStorage(ReferenceLines.lowKey) private var referenceLow = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var referenceHigh = ReferenceLines.defaultHigh
    @State private var quickAdd: QuickAddModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    SensorStatusChip(state: viewModel.sensor.state)
                    if viewModel.hasNoData {
                        TodayEmptyView(sensor: viewModel.sensor)
                    } else {
                        if viewModel.isToday {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                CurrentValueView(viewModel: viewModel, now: context.date)
                            }
                        }
                        if viewModel.failure != nil {
                            Label(
                                String(localized: "today.failure", defaultValue: "No se pudieron leer los datos guardados."),
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(Tokens.Palette.error)
                        }
                        PeriodPicker(period: periodBinding, isEnabled: viewModel.isToday)
                        GlucoseChartCard(viewModel: viewModel)
                        TodayEntriesRow(count: viewModel.dayEntryCount, isToday: viewModel.isToday)
                        PeriodStatsCard(stats: viewModel.stats, period: viewModel.period)
                    }
                    if viewModel.isSynthetic {
                        Label(
                            String(localized: "today.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real."),
                            systemImage: "testtube.2"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Tokens.Spacing.sm)
            }
            // Barra inferior propia: el contenido termina sobre el "+" y el último elemento siempre queda visible.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    TodayAddButton { quickAdd = makeQuickAdd() }
                }
            }
            .navigationTitle(String(localized: "today.title", defaultValue: "Hoy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { DayNavigator(viewModel: viewModel) }
            }
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .sensor:
                    SensorView(viewModel: sensorViewModel)
                case .entries:
                    TodayEntriesView(day: viewModel.shownDay, store: viewModel.diaryStore, calendar: viewModel.calendar)
                }
            }
            .sheet(item: $quickAdd) { model in
                QuickAddSheet(model: model) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .modifier(TodayLifecycle(viewModel: viewModel, storedHours: $storedHours, referenceLow: $referenceLow, referenceHigh: $referenceHigh))
    }

    private var periodBinding: Binding<TodayPeriod> {
        Binding(
            get: { viewModel.period },
            set: { newValue in
                viewModel.period = newValue
                storedHours = newValue.rawValue
            }
        )
    }

    private func makeQuickAdd() -> QuickAddModel {
        let now = viewModel.now
        let calendar = viewModel.calendar
        // Hoy: ahora. Otro día: la misma hora del reloj en ese día.
        let at: Date = viewModel.isToday
            ? now
            : calendar.date(
                bySettingHour: calendar.component(.hour, from: now),
                minute: calendar.component(.minute, from: now), second: 0, of: viewModel.shownDay) ?? now
        return QuickAddModel(store: viewModel.diaryStore, at: at, calendar: calendar)
    }
}

/// Carga de datos, preferencias y primer plano de Hoy.
private struct TodayLifecycle: ViewModifier {
    let viewModel: TodayViewModel
    @Binding var storedHours: Int
    @Binding var referenceLow: Int
    @Binding var referenceHigh: Int
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await viewModel.observe() }
            .task(id: viewModel.windowKey) { await viewModel.refresh() }
            .onChange(of: referenceLow, initial: true) { syncReferences() }
            .onChange(of: referenceHigh, initial: true) { syncReferences() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                HealthDrainTrigger.current?.sceneDidBecomeActive()
                Task { await viewModel.refresh() }
            }
            .onAppear {
                if let stored = TodayPeriod(rawValue: storedHours), stored != viewModel.period { viewModel.period = stored }
                // Al volver desde el Diario hay marcas nuevas, editadas o borradas.
                Task { await viewModel.refresh() }
            }
            .sensoryFeedback(.warning, trigger: viewModel.sensor.state) { _, newState in
                newState == .stale
            }
    }

    private func syncReferences() {
        let normalized = ReferenceLines.normalized(low: referenceLow, high: referenceHigh)
        viewModel.referenceLow = normalized.low
        viewModel.referenceHigh = normalized.high
    }
}

#Preview {
    let data = PreviewData()
    return TodayView(
        viewModel: TodayViewModel(dataSource: data, sensorSource: data),
        sensorViewModel: SensorViewModel(statusSource: data)
    )
}
