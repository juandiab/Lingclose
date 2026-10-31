import SwiftUI

/// Título de sección del PDF con subtítulo opcional (T-34). Su alto lo fija `MedicalPDFLayout.titleHeight`.
struct MedicalPDFSectionTitle: View {
    let title: String
    var subtitle: String?
    var height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.system(size: MedicalPDFLayout.tableTitleSize, weight: .semibold))
                .foregroundStyle(MedicalPDFPalette.accent)
                .lineLimit(1)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: MedicalPDFLayout.subtitleSize))
                    .foregroundStyle(MedicalPDFPalette.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(width: MedicalPDFLayout.contentWidth, height: height, alignment: .topLeading)
    }
}
