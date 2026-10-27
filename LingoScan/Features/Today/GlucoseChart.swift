import Charts
import SwiftUI

/// Curva de glucosa con Swift Charts: un `LineMark` por tramo (los huecos quedan abiertos, sin interpolar),
/// banda de referencia, huecos sombreados y marcas de comidas y ejercicio.
struct GlucoseChart: View {
    let viewModel: TodayViewModel
    @Binding var selectedDate: Date?

    var body: some View {
        let domain = viewModel.chartValueDomain
        Chart {
            RectangleMark(
                xStart: .value("Inicio", viewModel.windowStart),
                xEnd: .value("Fin", viewModel.windowEnd),
                yStart: .value("Mínimo", Tokens.ReferenceRange.lower),
                yEnd: .value("Máximo", Tokens.ReferenceRange.upper)
            )
            .foregroundStyle(Tokens.Palette.inRange.opacity(0.14))

            ForEach(viewModel.gaps) { gap in
                RectangleMark(
                    xStart: .value("Inicio del hueco", gap.start),
                    xEnd: .value("Fin del hueco", gap.end),
                    yStart: .value("Mínimo", domain.lowerBound),
                    yEnd: .value("Máximo", domain.upperBound)
                )
                .foregroundStyle(Tokens.Palette.gap.opacity(0.22))
            }

            ForEach(viewModel.marks) { mark in
                RuleMark(x: .value("Marca", mark.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Image(systemName: mark.kind.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(mark.kind.title)
                    }
            }

            ForEach(viewModel.segments) { segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Hora", point.date),
                        y: .value("mg/dL", point.value),
                        series: .value("Tramo", segment.id)
                    )
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if segment.points.count == 1, let only = segment.points.first {
                    PointMark(x: .value("Hora", only.date), y: .value("mg/dL", only.value))
                        .foregroundStyle(.primary)
                        .symbolSize(24)
                }
            }

            if let selected = selectedDate.flatMap(viewModel.nearestPoint(to:)) {
                RuleMark(x: .value("Selección", selected.date))
                    .foregroundStyle(.secondary)
                PointMark(x: .value("Hora", selected.date), y: .value("mg/dL", selected.value))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: viewModel.windowStart...viewModel.windowEnd)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: viewModel.period.axisStrideHours)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityChartDescriptor(
            GlucoseChartDescriptor(
                points: viewModel.points,
                start: viewModel.windowStart,
                end: viewModel.windowEnd,
                valueDomain: domain,
                periodTitle: viewModel.period.spokenTitle
            )
        )
        .containerRelativeFrame(.vertical) { height, _ in height * 0.32 }
    }
}
