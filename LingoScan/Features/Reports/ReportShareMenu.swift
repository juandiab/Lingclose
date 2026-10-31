import SwiftUI

/// Compartir el reporte: PDF para el médico (T-34), resumen como imagen o datos (`ReportSnapshot` en JSON).
struct ReportShareMenu: View {
    let content: ReportContent
    let isSynthetic: Bool

    @Environment(\.reportAnalysisHealth) private var health
    @Environment(\.mealAssistant) private var mealAssistant
    @State private var showingMedicalReport = false

    var body: some View {
        Menu(String(localized: "reports.share", defaultValue: "Compartir"), systemImage: "square.and.arrow.up") {
            Button {
                showingMedicalReport = true
            } label: {
                Label(String(localized: "reports.share.medical", defaultValue: "Reporte para el médico (PDF)"),
                      systemImage: "doc.richtext")
            }
            ShareLink(
                item: ReportSummaryImageExport(bundle: content.bundle, isSynthetic: isSynthetic),
                preview: SharePreview(
                    String(localized: "reports.share.image.preview", defaultValue: "Resumen de glucosa"),
                    image: Image(systemName: "chart.bar.doc.horizontal"))
            ) {
                Label(String(localized: "reports.share.image", defaultValue: "Resumen como imagen"), systemImage: "photo")
            }
            ShareLink(
                item: ReportSnapshotExport(bundle: content.bundle),
                preview: SharePreview(
                    String(localized: "reports.share.json.preview", defaultValue: "Datos del reporte (JSON)"),
                    image: Image(systemName: "curlybraces"))
            ) {
                Label(String(localized: "reports.share.json", defaultValue: "Datos del reporte (JSON)"), systemImage: "curlybraces")
            }
        }
        .sheet(isPresented: $showingMedicalReport) {
            MedicalReportSheet(content: content, isSynthetic: isSynthetic, health: health, nutrition: mealAssistant.nutrition)
        }
    }
}
