import SwiftUI

/// Línea sobre la curva: el período visible o, al arrastrar, "N mg/dL a las HH:MM" (o "Sin lectura").
struct SelectionReadout: View {
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        Group {
            if let date = selection.date {
                if let point = viewModel.nearestPoint(to: date) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                        MetricText(value: point.value, unit: "mg/dL", size: .large)
                        Text(String(localized: "today.readout.at", defaultValue: "a las \(point.date.formatted(date: .omitted, time: .shortened))"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(viewModel.readoutText(at: date))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(header)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var header: String {
        viewModel.isToday
            ? String(localized: "today.chart.header", defaultValue: "Últimas \(viewModel.period.hours) horas")
            : viewModel.shownDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
