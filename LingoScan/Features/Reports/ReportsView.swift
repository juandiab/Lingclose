import LingoCore
import SwiftUI

/// Reportes (T-27c): selector de período en vidrio y una card por reporte (resumen, perfil por hora, días
/// superpuestos, semana a semana, comidas, noche, ejercicio y franjas), cada una con su detalle y su estado vacío.
/// Compartir (JSON e imagen) en la barra; "Analizar con IA" si el entorno trae `reportAnalysisEntry`.
struct ReportsView: View {
    @State private var viewModel: ReportsViewModel
    @State private var analysisItem: ReportsAnalysisSheetItem?
    @Namespace private var namespace
    @AppStorage(ReferenceLines.lowKey) private var referenceLow = ReferenceLines.defaultLow
    @AppStorage(ReferenceLines.highKey) private var referenceHigh = ReferenceLines.defaultHigh
    @Environment(\.reportAnalysisEntry) private var analysisEntry
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: ReportsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    ReportsPeriodPicker(selection: viewModel.preset, onSelect: select)
                    ReportsPeriodCaption(content: viewModel.content, isLoading: viewModel.isLoading)
                    if analysisEntry != nil {
                        ReportAnalyzeButton(isEnabled: canAnalyze, action: analyze)
                    }
                    if let content = viewModel.content {
                        if viewModel.failure != nil {
                            ReportsStatusCard(isFailure: true, onRetry: retry)
                        }
                        ReportCardsList(content: content, namespace: namespace)
                            .opacity(viewModel.isShowingStaleContent ? 0.45 : 1)
                            .animation(Motion.animation(Motion.smooth, reduceMotion: reduceMotion), value: viewModel.isShowingStaleContent)
                    } else {
                        ReportsStatusCard(isFailure: viewModel.failure != nil && !viewModel.isLoading, onRetry: retry)
                    }
                    ReportsFooter(range: viewModel.configuration.range, isSynthetic: viewModel.isSynthetic)
                }
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.top, Tokens.Spacing.xs)
                .padding(.bottom, Tokens.Spacing.md)
            }
            .navigationTitle(String(localized: "reports.title", defaultValue: "Reportes"))
            .appBackground()
            .toolbar {
                if let content = viewModel.content, content.hasData, !viewModel.isShowingStaleContent {
                    ToolbarItem(placement: .topBarTrailing) {
                        ReportShareMenu(content: content, isSynthetic: viewModel.isSynthetic)
                    }
                }
            }
            .navigationDestination(for: ReportRoute.self) { route in
                if let content = viewModel.content {
                    ReportDetailView(route: route, content: content, namespace: namespace)
                }
            }
            .sheet(item: $analysisItem) { item in
                analysisEntry?.makeSheet(item.bundle)
            }
        }
        .task { await viewModel.appear() }
        // El rango de referencia de Ajustes (el mismo de Hoy); también al aparecer.
        .task(id: [referenceLow, referenceHigh]) {
            await viewModel.updateReference(low: referenceLow, high: referenceHigh)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.sceneDidBecomeActive() }
        }
    }

    private var canAnalyze: Bool {
        guard let content = viewModel.content else { return false }
        return content.hasData && !viewModel.isShowingStaleContent
    }

    private func select(_ preset: ReportPeriod.Preset) {
        Task { await viewModel.select(preset) }
    }

    private func analyze() {
        guard canAnalyze, let content = viewModel.content else { return }
        analysisItem = ReportsAnalysisSheetItem(bundle: content.bundle)
    }

    private func retry() {
        Task { await viewModel.retry() }
    }
}

#Preview("Datos sintéticos") {
    ReportsView(viewModel: .preview())
}

#Preview("Sin datos") {
    ReportsView(viewModel: ReportsViewModel(dataSource: EmptyReportsDataSource()))
}
