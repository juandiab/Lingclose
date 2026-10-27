import Charts
import SwiftUI

/// Curva de glucosa con Swift Charts: un `LineMark` por tramo (los huecos quedan abiertos, sin interpolar),
/// líneas de referencia, área sombreada sobre la línea alta en cada pico y huecos sombreados.
/// Marcas, índices de pico y cursor se dibujan en `ChartInteractionOverlay`.
struct GlucoseChart: View {
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        let domain = viewModel.chartValueDomain
        let high = viewModel.referenceHigh
        let low = viewModel.referenceLow
        Chart {
            ForEach(viewModel.gaps) { gap in
                RectangleMark(
                    xStart: .value("Inicio del hueco", gap.start),
                    xEnd: .value("Fin del hueco", gap.end),
                    yStart: .value("Mínimo", domain.lowerBound),
                    yEnd: .value("Máximo", domain.upperBound)
                )
                .foregroundStyle(Tokens.Palette.gap.opacity(0.22))
            }

            RuleMark(y: .value("Referencia alta", high))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text(String(localized: "today.reference.value", defaultValue: "\(high) mg/dL"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            RuleMark(y: .value("Referencia baja", low))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text(String(localized: "today.reference.value", defaultValue: "\(low) mg/dL"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            ForEach(viewModel.segments) { segment in
                // Área sobre la línea alta: cada punto se recorta a `max(valor, referencia alta)`.
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("Hora", point.date),
                        yStart: .value("Referencia alta", high),
                        yEnd: .value("Exceso", max(point.value, high)),
                        series: .value("Pico", segment.id)
                    )
                    .foregroundStyle(Tokens.Palette.outOfRange.opacity(0.3))
                }
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
        }
        .chartXScale(domain: viewModel.windowStart...viewModel.windowEnd)
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: viewModel.isToday ? viewModel.period.axisStrideHours : 4)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartOverlay { proxy in
            ChartInteractionOverlay(proxy: proxy, viewModel: viewModel, selection: selection)
        }
        .accessibilityChartDescriptor(
            GlucoseChartDescriptor(
                points: viewModel.points,
                start: viewModel.windowStart,
                end: viewModel.windowEnd,
                valueDomain: domain,
                periodTitle: viewModel.isToday ? viewModel.period.spokenTitle : viewModel.shownDay.formatted(date: .complete, time: .omitted),
                referenceLow: viewModel.referenceLow,
                referenceHigh: viewModel.referenceHigh
            )
        )
        .containerRelativeFrame(.vertical) { height, _ in height * 0.36 }
    }
}
