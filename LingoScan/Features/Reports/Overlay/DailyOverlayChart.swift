import Charts
import LingoCore
import SwiftUI

/// Días superpuestos: una línea tenue por día sobre el mismo eje de 24 h y el último día (hoy) resaltado.
/// Los huecos quedan abiertos (cada tramo es una serie).
struct DailyOverlayChart: View {
    let points: [OverlayPoint]
    let configuration: ReportConfiguration
    let dayCount: Int

    var body: some View {
        let domain = Self.valueDomain(points: points, configuration: configuration)
        Chart {
            RuleMark(y: .value("Referencia alta", configuration.rangeHigh))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(ReportPalette.referenceStroke)
            RuleMark(y: .value("Referencia baja", configuration.rangeLow))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(ReportPalette.referenceStroke)
            ForEach(points) { point in
                LineMark(
                    x: .value("Hora", point.minute),
                    y: .value("mg/dL", point.value),
                    series: .value("Día", point.series))
                    .foregroundStyle(point.isLatest ? Color.primary : Color.secondary.opacity(0.32))
                    .lineStyle(StrokeStyle(lineWidth: point.isLatest ? 2.5 : 1, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: 0...1_440)
        .chartYScale(domain: domain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: [0, 360, 720, 1_080, 1_440]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel {
                    if let minute = value.as(Int.self) {
                        Text(ReportFormat.hour(minute: minute % 1_440))
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [configuration.rangeLow, configuration.rangeHigh]) { _ in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "reports.overlay.chart.a11y", defaultValue: "Días superpuestos"))
        .accessibilityValue(String(
            localized: "reports.overlay.chart.value",
            defaultValue: "\(dayCount) días sobre un eje de 24 horas; el último día, resaltado."))
    }

    static func valueDomain(points: [OverlayPoint], configuration: ReportConfiguration) -> ClosedRange<Int> {
        let lowest = min(points.map(\.value).min() ?? 100, configuration.rangeLow)
        let highest = max(points.map(\.value).max() ?? 160, configuration.rangeHigh)
        return max(0, (lowest - 10) / 20 * 20)...((highest + 29) / 20 * 20)
    }
}
