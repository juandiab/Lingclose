import LingoCore
import SwiftUI

/// Pantalla Hoy: navegación por día, valor actual, curva desplazable con zoom (chips 3/6/12/24 h y pellizco),
/// picos, marcas y cursor, fila de registro y "+" para anotar en dos toques.
struct TodayView: View {
    @Bindable var viewModel: TodayViewModel
    let sensorViewModel: SensorViewModel

    @AppStorage(TodayPeriod.storageKey) private var storedHours = TodayPeriod.sixHours.rawValue
    @AppStorage(TodayViewModel.visibleSecondsKey) private var storedSeconds = 0.0
    @AppStorage(ReferenceLines.lowKey) private var referenceLow = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var referenceHigh = ReferenceLines.defaultHigh
    @State private var quickAdd: QuickAddModel?
    @State private var mealAnalysis: MealAnalysisViewModel?
    @Environment(\.mealAssistant) private var mealServices
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    SensorStatusChip(state: viewModel.sensor.state)
                    if viewModel.hasNoData {
                        TodayEmptyView(sensor: viewModel.sensor)
                    } else {
                        // El último valor es independiente de la ventana visible: se ve también al mirar otro día.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            CurrentValueView(viewModel: viewModel, now: context.date)
                        }
                        if viewModel.failure != nil {
                            Label(
                                String(localized: "today.failure", defaultValue: "No se pudieron leer los datos guardados."),
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(Tokens.Palette.error)
                        }
                        PeriodPicker(viewModel: viewModel) { selectPeriod($0) }
                        GlucoseChartCard(viewModel: viewModel)
                        TodayEntriesRow(count: viewModel.dayEntryCount, isToday: viewModel.isToday)
                        PeriodStatsCard(
                            stats: viewModel.stats,
                            lengthTitle: GlucoseChart.lengthTitle(viewModel.windowEnd.timeIntervalSince(viewModel.windowStart))
                        )
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
                    TodayAddMenu { kind in choose(kind) }
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
            .sheet(item: $mealAnalysis) { analysis in
                MealAnalysisView(model: analysis, onSaved: {
                    Task { await viewModel.refresh() }
                }, onManualEntry: {
                    // "Entrada manual" desde la cámara: se cierra el análisis y se abre el registro de comida a mano.
                    mealAnalysis = nil
                    quickAdd = makeQuickAdd(preselecting: .meal)
                })
            }
        }
        .modifier(TodayLifecycle(
            viewModel: viewModel,
            storedHours: storedHours,
            storedSeconds: storedSeconds,
            referenceLow: $referenceLow,
            referenceHigh: $referenceHigh
        ))
    }

    /// Chip: fija la longitud visible conservando el fin de la ventana; anima salvo con Reduce Motion.
    private func selectPeriod(_ period: TodayPeriod) {
        withAnimation(reduceMotion ? nil : .snappy) { viewModel.setVisibleLength(period.duration) }
        storedHours = period.rawValue
        storedSeconds = period.duration
    }

    /// Comida: directo a "Analizar con IA" con la cámara abierta (si el asistente está configurado y hay cámara).
    /// Ejercicio y nota: registro rápido con el tipo ya elegido.
    private func choose(_ kind: DiaryEventKind) {
        switch kind {
        case .meal:
            mealAnalysis = MealAnalysisViewModel(services: mealServices, at: quickAddDate(), autoCamera: true)
        case .exercise, .note, .sensorNote:
            quickAdd = makeQuickAdd(preselecting: kind)
        }
    }

    private func makeQuickAdd(preselecting kind: DiaryEventKind? = nil) -> QuickAddModel {
        let model = QuickAddModel(store: viewModel.diaryStore, at: quickAddDate(), calendar: viewModel.calendar)
        if let kind { model.choose(kind) }
        return model
    }

    private func quickAddDate() -> Date {
        let now = viewModel.now
        let calendar = viewModel.calendar
        // En vivo: ahora. Otro día: la misma hora del reloj en ese día.
        return viewModel.isToday && viewModel.isLive
            ? now
            : calendar.date(
                bySettingHour: calendar.component(.hour, from: now),
                minute: calendar.component(.minute, from: now), second: 0, of: viewModel.shownDay) ?? now
    }
}

/// Carga de datos, preferencias y primer plano de Hoy.
private struct TodayLifecycle: ViewModifier {
    let viewModel: TodayViewModel
    let storedHours: Int
    let storedSeconds: Double
    @Binding var referenceLow: Int
    @Binding var referenceHigh: Int
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRestoreLength = false

    func body(content: Content) -> some View {
        content
            .task { await viewModel.observe() }
            .onChange(of: referenceLow, initial: true) { syncReferences() }
            .onChange(of: referenceHigh, initial: true) { syncReferences() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                HealthDrainTrigger.current?.sceneDidBecomeActive()
                WorkoutImportTrigger.current?.sceneDidBecomeActive()
                Task { await viewModel.refresh() }
            }
            .onAppear {
                restoreLength()
                // Primera carga y, al volver desde el Diario, marcas nuevas, editadas o borradas.
                Task { await viewModel.refresh() }
            }
            .sensoryFeedback(.warning, trigger: viewModel.sensor.state) { _, newState in
                newState == .stale
            }
    }

    /// Al abrir: la longitud libre guardada (pellizco) o, si no hay, la del último chip.
    private func restoreLength() {
        guard !didRestoreLength else { return }
        didRestoreLength = true
        let hours = TodayPeriod(rawValue: storedHours)?.duration ?? TodayViewModel.defaultVisibleLength
        let length = storedSeconds > 0 ? storedSeconds : hours
        if abs(length - viewModel.visibleLength) > 1 { viewModel.setVisibleLength(length) }
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
