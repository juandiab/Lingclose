import SwiftUI

/// Página 1 del PDF: datos del paciente, período y sensor, métricas y tiempo en rangos (T-34). Alto fijo
/// (`MedicalReportFlow.summaryHeight`).
struct MedicalPDFSummaryView: View {
    let document: MedicalReportDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleBlock
            HStack(alignment: .top, spacing: 20) {
                factsCard(title: MedicalReportStrings.patientTitle, facts: document.patientFacts, labelWidth: 100)
                    .frame(width: 304, alignment: .topLeading)
                factsCard(title: MedicalReportStrings.periodTitle, facts: document.periodFacts, labelWidth: 78)
                    .frame(width: 216, alignment: .topLeading)
            }
            .frame(height: 188, alignment: .top)
            metricTiles
            rangesBlock
        }
        .frame(width: MedicalPDFLayout.contentWidth, height: MedicalReportFlow.summaryHeight, alignment: .topLeading)
    }

    // MARK: Título

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: MedicalReportStrings.documentTitle)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(MedicalPDFPalette.ink)
            Text(verbatim: MedicalReportStrings.documentSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(MedicalPDFPalette.secondary)
            if document.isSynthetic {
                Text(verbatim: MedicalReportStrings.syntheticNote)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(MedicalPDFPalette.band(.low))
            }
        }
        .frame(height: 68, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(MedicalPDFPalette.hairline).frame(height: 0.8) }
    }

    // MARK: Datos

    private func factsCard(title: String, facts: [MedicalFact], labelWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MedicalPDFPalette.accent)
                .padding(.bottom, 2)
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: fact.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MedicalPDFPalette.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                        .lineLimit(2)
                    Text(verbatim: fact.value)
                        .font(.system(size: 9, weight: fact.isAvailable ? .semibold : .regular))
                        .foregroundStyle(fact.isAvailable ? MedicalPDFPalette.ink : MedicalPDFPalette.tertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    // MARK: Métricas

    private var metricTiles: some View {
        HStack(spacing: 10) {
            ForEach(Array(document.metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: metric.label)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundStyle(MedicalPDFPalette.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .topLeading)
                    Text(verbatim: metric.value)
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(MedicalPDFPalette.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 62)
                .background(MedicalPDFPalette.tile, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(width: MedicalPDFLayout.contentWidth, height: 62)
    }

    // MARK: Tiempo en rangos

    private var rangesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: MedicalReportStrings.rangesTitle(document.unitSymbol))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MedicalPDFPalette.accent)
            if document.hasGlucoseData {
                stackedBar
                Text(verbatim: MedicalReportStrings.rangesPerDay)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(MedicalPDFPalette.secondary)
                    .frame(width: MedicalPDFLayout.contentWidth, alignment: .trailing)
                VStack(spacing: 0) {
                    ForEach(document.rangeRows.reversed(), id: \.band) { row in rangeRow(row) }
                }
                if let line = document.personalRangeLine {
                    Text(verbatim: line)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(MedicalPDFPalette.secondary)
                }
            }
        }
    }

    private var stackedBar: some View {
        HStack(spacing: 1) {
            ForEach(document.rangeRows, id: \.band) { row in
                let width = max(0, (MedicalPDFLayout.contentWidth - 4) * CGFloat(row.fraction))
                Rectangle()
                    .fill(MedicalPDFPalette.band(row.band))
                    .frame(width: width, height: 26)
                    .overlay {
                        if width > 34 {
                            Text(verbatim: row.percentText)
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(row.band == .high ? MedicalPDFPalette.ink : .white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
            }
        }
        .frame(width: MedicalPDFLayout.contentWidth, height: 26, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func rangeRow(_ row: MedicalRangeRow) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(MedicalPDFPalette.band(row.band)).frame(width: 10, height: 10)
            Text(verbatim: row.name)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 70, alignment: .leading)
            Text(verbatim: row.rangeText)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(MedicalPDFPalette.secondary)
                .frame(width: 110, alignment: .leading)
            Spacer(minLength: 0)
            Text(verbatim: row.percentText)
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            Text(verbatim: row.perDayText)
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(MedicalPDFPalette.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .foregroundStyle(MedicalPDFPalette.ink)
        .frame(height: 19)
        .overlay(alignment: .bottom) { Rectangle().fill(MedicalPDFPalette.hairline.opacity(0.7)).frame(height: 0.5) }
    }
}
