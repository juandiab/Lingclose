import SwiftUI

/// Tramo de la rejilla de perfiles diarios: 7 mini-curvas por fila, las filas `range` (T-34).
struct MedicalPDFDailyGridView: View {
    let document: MedicalReportDocument
    let range: Range<Int>
    let isContinuation: Bool

    var body: some View {
        let columns = MedicalPDFLayout.dailyColumns
        let gap = MedicalPDFLayout.dailyGap
        let cellWidth = (MedicalPDFLayout.contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        VStack(alignment: .leading, spacing: 0) {
            if isContinuation {
                MedicalPDFSectionTitle(
                    title: document.dailyTitle + " " + MedicalReportStrings.continued, subtitle: nil,
                    height: MedicalPDFLayout.continuationTitleHeight(title: document.dailyTitle))
            } else {
                MedicalPDFSectionTitle(
                    title: document.dailyTitle, subtitle: document.dailySubtitle,
                    height: MedicalPDFLayout.titleHeight(title: document.dailyTitle, subtitle: document.dailySubtitle))
            }
            ForEach(range, id: \.self) { row in
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < document.dailyProfiles.count {
                            cell(document.dailyProfiles[index], width: cellWidth)
                        } else {
                            Color.clear.frame(width: cellWidth, height: MedicalPDFLayout.dailyCellHeight)
                        }
                    }
                }
                .frame(width: MedicalPDFLayout.contentWidth, height: MedicalPDFLayout.dailyCellHeight + gap, alignment: .topLeading)
            }
        }
        .frame(width: MedicalPDFLayout.contentWidth, alignment: .topLeading)
    }

    private func cell(_ profile: MedicalDailyProfile, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: profile.label)
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(MedicalPDFPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            MedicalPDFMiniCurve(values: profile.values, targetLow: document.targetLow, targetHigh: document.targetHigh,
                                width: width, height: 50)
            Text(verbatim: profile.caption)
                .font(.system(size: 7))
                .monospacedDigit()
                .foregroundStyle(MedicalPDFPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: width, height: MedicalPDFLayout.dailyCellHeight, alignment: .topLeading)
    }
}
