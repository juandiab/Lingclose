import SwiftUI

/// Línea sobre la curva: el período visible o, al tocar, el valor y la hora del punto elegido.
struct SelectionReadout: View {
    let point: GlucosePoint?
    let period: TodayPeriod

    var body: some View {
        Group {
            if let point {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                    MetricText(value: point.value, unit: "mg/dL", size: .large)
                    Text(point.date, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "today.chart.header", defaultValue: "Últimas \(period.hours) horas"))
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
