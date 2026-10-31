import SwiftUI

/// Tramo de "Notas y método": los párrafos `range` (T-34).
struct MedicalPDFMethodView: View {
    let paragraphs: [String]
    let range: Range<Int>
    let isContinuation: Bool

    var body: some View {
        let title = MedicalReportStrings.methodTitle
        VStack(alignment: .leading, spacing: 0) {
            MedicalPDFSectionTitle(
                title: isContinuation ? title + " " + MedicalReportStrings.continued : title, subtitle: nil,
                height: isContinuation
                    ? MedicalPDFLayout.continuationTitleHeight(title: title)
                    : MedicalPDFLayout.titleHeight(title: title, subtitle: nil))
            ForEach(range, id: \.self) { index in
                Text(verbatim: paragraphs[index])
                    .font(.system(size: MedicalReportFlow.methodTextSize))
                    .foregroundStyle(MedicalPDFPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: MedicalPDFLayout.contentWidth, height: CGFloat(MedicalReportFlow.methodRowHeight(paragraphs[index])),
                           alignment: .topLeading)
            }
        }
        .frame(width: MedicalPDFLayout.contentWidth, alignment: .topLeading)
    }
}
