import LingoCore
import SwiftUI

/// Historial de análisis del mismo tramo de días: tocar uno lo vuelve a mostrar (sin llamar al proveedor) y se puede borrar.
struct ReportAnalysisHistoryView: View {
    let service: ReportAnalysisService
    @State private var pendingDeletion: ReportAnalysisRecord?
    @State private var isConfirmingDeletion = false

    var body: some View {
        if !service.history.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(String(localized: "reports.analysis.history.title", defaultValue: "Análisis anteriores"))
                    .font(.headline)
                    .foregroundStyle(Tokens.Studio.textPrimary)
                ForEach(service.history) { record in
                    row(record)
                }
            }
            .padding(Tokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioCard()
            .confirmationDialog(
                String(localized: "reports.analysis.history.deleteTitle", defaultValue: "¿Borrar este análisis?"),
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible, presenting: pendingDeletion
            ) { record in
                Button(String(localized: "reports.analysis.history.delete", defaultValue: "Borrar"), role: .destructive) {
                    Task { await service.delete(record) }
                }
            } message: { _ in
                Text(String(localized: "reports.analysis.history.deleteMessage", defaultValue: "Solo se borra de este iPhone."))
            }
        }
    }

    private func row(_ record: ReportAnalysisRecord) -> some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Button { service.show(record) } label: {
                HStack(spacing: Tokens.Spacing.xs) {
                    Image(systemName: symbol(for: record.status))
                        .foregroundStyle(record.status == .succeeded ? Tokens.Palette.inRange : Tokens.Studio.textSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.createdAt.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(Tokens.Studio.textPrimary)
                        Text(detail(record))
                            .font(.caption)
                            .foregroundStyle(Tokens.Studio.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(service.shownRecordID == record.id ? .isSelected : [])

            Button(String(localized: "reports.analysis.history.delete", defaultValue: "Borrar"), systemImage: "trash") {
                pendingDeletion = record
                isConfirmingDeletion = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(Tokens.Studio.textSecondary)
        }
    }

    private func symbol(for status: ReportAnalysisStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle"
        case .rejected: "hand.raised"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func label(for status: ReportAnalysisStatus) -> String {
        switch status {
        case .succeeded: String(localized: "reports.analysis.status.succeeded", defaultValue: "Guardado")
        case .rejected: String(localized: "reports.analysis.status.rejected", defaultValue: "Descartado")
        case .failed: String(localized: "reports.analysis.status.failed", defaultValue: "Con error")
        }
    }

    private func detail(_ record: ReportAnalysisRecord) -> String {
        let days = ReportAnalysisService.spanDays(start: record.periodStart, end: record.periodEnd)
        let range = "\(record.periodStart.date.formatted(.dateTime.day().month(.abbreviated))) – \(record.periodEnd.date.formatted(.dateTime.day().month(.abbreviated)))"
        let daysText = String(localized: "reports.analysis.intro.days", defaultValue: "\(days) días")
        return "\(label(for: record.status)) · \(daysText) (\(range)) · \(record.model)"
    }
}
