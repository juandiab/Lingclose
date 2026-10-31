import LingoCore
import SwiftUI

/// Una franja del día: media, barra de bandas, tiempo en rango y subidas rápidas por día. En el detalle, además SD,
/// CV, mínimo, máximo y bajadas rápidas.
struct TimeOfDaySlotRow: View {
    let slot: TimeOfDayPatternsReport.Slot
    var showsDetail = false

    var body: some View {
        let stats = slot.stats
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReportNames.slot(slot.slot))
                    .font(.subheadline.weight(.semibold))
                Text(ReportNames.slotHours(slot.slot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Tokens.Spacing.xs)
                if stats.hasReadings {
                    Text(String(
                        localized: "reports.slot.values",
                        defaultValue: "media \(ReportFormat.mgdl(stats.mean) ?? "--") · \(ReportFormat.percent(stats.timeInRange) ?? "--") en rango"))
                        .font(.footnote)
                        .monospacedDigit()
                }
            }
            if stats.hasReadings {
                ReportBandBar(stats: stats, height: 8)
            }
            Text(note)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            if showsDetail, slot.isReliable {
                ReportStatGrid {
                    ReportStatTile(title: String(localized: "reports.stat.sd", defaultValue: "SD"), value: ReportFormat.mgdl(stats.standardDeviation), unit: "mg/dL")
                    ReportStatTile(title: String(localized: "reports.stat.cv", defaultValue: "CV"), value: ReportFormat.percent(stats.coefficientOfVariation))
                    ReportStatTile(title: String(localized: "reports.stat.min", defaultValue: "Mínimo"), value: stats.minimum.map { "\($0)" }, unit: "mg/dL")
                    ReportStatTile(title: String(localized: "reports.stat.max", defaultValue: "Máximo"), value: stats.maximum.map { "\($0)" }, unit: "mg/dL")
                    ReportStatTile(
                        title: String(localized: "reports.slot.fastFalls", defaultValue: "Bajadas rápidas"),
                        value: slot.fastFallsPerDay.map { $0.formatted(.number.precision(.fractionLength(1))) },
                        unit: String(localized: "reports.slot.perDay", defaultValue: "por día"))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var note: String {
        guard slot.isReliable else {
            return String(
                localized: "reports.slot.tooFew",
                defaultValue: "\(slot.days) de \(ReportThresholds.minimumDaysPerTimeSlot) días necesarios para comparar esta franja.")
        }
        let rises = slot.fastRisesPerDay.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--"
        return String(
            localized: "reports.slot.rises",
            defaultValue: "\(rises) subidas rápidas por día · \(slot.days) días")
    }
}
