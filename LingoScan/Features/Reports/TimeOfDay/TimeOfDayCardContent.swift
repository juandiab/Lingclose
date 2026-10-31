import LingoCore
import SwiftUI

/// Card de patrones por franja: las cuatro franjas, o qué falta (≥ 3 días por franja).
struct TimeOfDayCardContent: View {
    let report: TimeOfDayPatternsReport
    let daysWithData: Int
    var showsDetail = false

    var body: some View {
        if report.hasEnoughData {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ForEach(report.slots, id: \.slot) { slot in
                    TimeOfDaySlotRow(slot: slot, showsDetail: showsDetail)
                    if slot.slot != report.slots.last?.slot { Divider() }
                }
            }
        } else {
            ReportEmptyState(message: String(
                localized: "reports.slots.empty",
                defaultValue: "Los patrones por franja necesitan al menos \(ReportThresholds.minimumDaysPerTimeSlot) días con lecturas en cada franja. Días con datos ahora: \(daysWithData)."))
        }
    }
}
