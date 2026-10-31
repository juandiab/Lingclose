import LingoCore
import SwiftUI

/// Una sesión de ejercicio: cuándo, duración y cambio de glucosa al terminar, a 1 h y a 2 h.
struct ExerciseSessionRow: View {
    let session: ExerciseEffectReport.Session

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(ReportFormat.dateTime(session.at))
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            if let effect = session.effect {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                    fact(String(localized: "reports.exercise.atEnd", defaultValue: "Al terminar"), effect.deltaAtEnd)
                    fact(String(localized: "reports.exercise.at60", defaultValue: "1 h después"), effect.deltaAt60)
                    fact(String(localized: "reports.exercise.at120", defaultValue: "2 h después"), effect.deltaAt120)
                }
            } else {
                Text(String(
                    localized: "reports.exercise.noEffect",
                    defaultValue: "Sin lecturas suficientes durante o después para medir el efecto."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [ReportNames.slot(session.slot)]
        if let minutes = session.durationMinutes { parts.append(ReportFormat.duration(minutes: minutes)) }
        if let effect = session.effect {
            parts.append(String(
                localized: "reports.exercise.baseline",
                defaultValue: "antes \(Int(effect.baseline.rounded())) mg/dL, mínimo \(effect.minimum)"))
        }
        return parts.joined(separator: " · ")
    }

    private func fact(_ title: String, _ delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: delta.map { ReportFormat.signed($0) } ?? "--")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
    }
}
