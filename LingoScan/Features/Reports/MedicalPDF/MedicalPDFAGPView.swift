import SwiftUI

/// Bloque del AGP: título, subtítulo, gráfica y leyenda (T-34). Su alto lo suma `MedicalReportFlow.agpHeight`.
struct MedicalPDFAGPView: View {
    let document: MedicalReportDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MedicalPDFSectionTitle(
                title: MedicalReportStrings.agpTitle, subtitle: MedicalReportStrings.agpSubtitle(document.unitSymbol),
                height: MedicalPDFLayout.titleHeight(title: MedicalReportStrings.agpTitle, subtitle: MedicalReportStrings.agpSubtitle(document.unitSymbol)))
            MedicalPDFAGPChart(agp: document.agp)
            legend.padding(.top, 8)
        }
        .frame(width: MedicalPDFLayout.contentWidth, alignment: .topLeading)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            item(MedicalReportStrings.agpMedian) {
                Rectangle().fill(MedicalPDFPalette.accent).frame(width: 16, height: 1.7)
            }
            item(MedicalReportStrings.agpIQR) {
                Rectangle().fill(MedicalPDFPalette.accent.opacity(0.30)).frame(width: 16, height: 8)
            }
            item(MedicalReportStrings.agpWide) {
                Rectangle().fill(MedicalPDFPalette.accent.opacity(0.14)).frame(width: 16, height: 8)
            }
            item(document.agp.targetLabel) {
                Rectangle().fill(MedicalPDFPalette.targetFill).frame(width: 16, height: 8)
                    .overlay { Rectangle().stroke(MedicalPDFPalette.targetLine, lineWidth: 0.6) }
            }
        }
        .frame(width: MedicalPDFLayout.contentWidth, height: MedicalPDFLayout.agpLegendHeight, alignment: .leading)
    }

    private func item<Swatch: View>(_ text: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 4) {
            swatch()
            Text(verbatim: text)
                .font(.system(size: 7.5))
                .foregroundStyle(MedicalPDFPalette.secondary)
        }
    }
}
