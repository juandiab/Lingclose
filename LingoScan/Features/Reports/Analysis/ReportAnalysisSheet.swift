import LingoCore
import SwiftUI

/// Hoja "Análisis con IA" de un reporte (T-27d): primero muestra qué se enviará y cuánto cuesta aproximadamente; el
/// análisis solo se pide al tocar "Analizar" (una petición por toque). Después muestra el resultado, el historial de
/// análisis del mismo tramo y, siempre, la nota de que es una guía y no un diagnóstico.
struct ReportAnalysisSheet: View {
    let bundle: ReportBundle
    let service: ReportAnalysisService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    content
                    ReportAnalysisHistoryView(service: service)
                }
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.vertical, Tokens.Spacing.sm)
                .animation(Motion.animation(Motion.smooth, reduceMotion: reduceMotion), value: service.state)
            }
            .navigationTitle(String(localized: "reports.analysis.title", defaultValue: "Análisis con IA"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "reports.analysis.done", defaultValue: "Listo")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ReportAnalysisDisclaimer()
            }
        }
        .task { await service.prepare(for: bundle) }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .idle:
            if service.isConfigured {
                ReportAnalysisIntroView(
                    outgoing: service.outgoing,
                    modelLabel: service.modelLabel,
                    hasPricing: service.model?.pricing != nil,
                    canAnalyze: bundle.hasData,
                    analyze: { service.analyze(bundle) })
            } else {
                ReportAnalysisNotConfiguredView()
            }
        case .loading:
            ReportAnalysisLoadingView(modelLabel: service.modelLabel)
        case .done(let reply):
            ReportAnalysisResultView(reply: reply)
            Button(String(localized: "reports.analysis.again", defaultValue: "Analizar de nuevo"), systemImage: "arrow.clockwise") {
                service.analyze(bundle)
            }
            .buttonStyle(.bordered)
            .disabled(!service.isConfigured)
        case .rejected(let message):
            ReportAnalysisProblemView(
                symbol: "hand.raised",
                title: String(localized: "reports.analysis.rejected.title", defaultValue: "Respuesta descartada"),
                message: message, canRetry: service.isConfigured, retry: { service.analyze(bundle) })
        case .failed(let message):
            ReportAnalysisProblemView(
                symbol: "exclamationmark.triangle",
                title: String(localized: "reports.analysis.failed.title", defaultValue: "No se pudo analizar"),
                message: message, canRetry: service.isConfigured, retry: { service.analyze(bundle) })
        }
    }
}
