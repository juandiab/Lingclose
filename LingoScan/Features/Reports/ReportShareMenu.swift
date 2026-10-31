import SwiftUI

/// Compartir el reporte: datos (`ReportSnapshot` en JSON) o el resumen como imagen.
struct ReportShareMenu: View {
    let content: ReportContent
    let isSynthetic: Bool

    var body: some View {
        Menu(String(localized: "reports.share", defaultValue: "Compartir"), systemImage: "square.and.arrow.up") {
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
    }
}
