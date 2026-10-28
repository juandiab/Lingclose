import SwiftUI

/// Línea compacta sobre la curva: el período visible o, con el cursor, "N mg/dL a las HH:MM" (o "Sin lectura").
struct SelectionReadout: View {
    let viewModel: TodayViewModel
    let selection: ChartSelection
    @ScaledMetric(relativeTo: .title3) private var lineHeight = 30.0

    var body: some View {
        Group {
            if let date = selection.date {
                if let point = viewModel.nearestPoint(to: date) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                        MetricText(value: point.value, unit: "mg/dL", size: .medium)
                        Text(String(localized: "today.readout.at", defaultValue: "a las \(point.date.formatted(date: .omitted, time: .shortened))"))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(viewModel.readoutText(at: date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(header)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // Alto fijo de la línea para que la curva no salte al poner o quitar el cursor.
        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// En vivo: "Últimas 4 h 30 min". En el pasado: el intervalo asentado ("08:15 – 14:15").
    private var header: String {
        if viewModel.isLive {
            let length = GlucoseChart.lengthTitle(viewModel.windowEnd.timeIntervalSince(viewModel.windowStart))
            return String(localized: "today.chart.header.live", defaultValue: "Últimas \(length)")
        }
        let interval = viewModel.windowStart..<viewModel.windowEnd
        if viewModel.calendar.isDate(interval.lowerBound, inSameDayAs: interval.upperBound) {
            return interval.formatted(.interval.hour().minute())
        }
        return interval.formatted(.interval.weekday(.abbreviated).hour().minute())
    }
}
