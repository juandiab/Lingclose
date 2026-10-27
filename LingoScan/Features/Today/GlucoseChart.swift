import Charts
import SwiftUI

/// Curva de glucosa con Swift Charts: un `LineMark` por tramo (los huecos quedan abiertos, sin interpolar),
/// líneas de referencia, área sombreada sobre la línea alta (rojo) y bajo la baja (azul), y huecos sombreados.
/// La línea lleva un degradado por valor: rojo por encima de la referencia alta, neutro en el rango y azul
/// por debajo de la baja (el degradado se aplica sobre el área del trazado, así que las paradas se calculan
/// con el dominio vertical).
/// Marcas, índices de pico y cursor se dibujan en `ChartInteractionOverlay`.
struct GlucoseChart: View {
    let viewModel: TodayViewModel
    let selection: ChartSelection

    var body: some View {
        let domain = viewModel.chartValueDomain
        let high = viewModel.referenceHigh
        let low = viewModel.referenceLow
        let lineGradient = Self.valueGradient(domain: domain, low: low, high: high)
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
                    .foregroundStyle(Tokens.Palette.high.opacity(0.18))
                }
                // Área bajo la línea baja: simétrica a la de los picos, en frío.
                ForEach(segment.points) { point in
                    AreaMark(
                        x: .value("Hora", point.date),
                        yStart: .value("Defecto", min(point.value, low)),
                        yEnd: .value("Referencia baja", low),
                        series: .value("Bajo", segment.id)
                    )
                    .foregroundStyle(Tokens.Palette.low.opacity(0.18))
                }
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Hora", point.date),
                        y: .value("mg/dL", point.value),
                        series: .value("Tramo", segment.id)
                    )
                    .foregroundStyle(lineGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if segment.points.count == 1, let only = segment.points.first {
                    PointMark(x: .value("Hora", only.date), y: .value("mg/dL", only.value))
                        .foregroundStyle(Self.color(for: only.value, low: low, high: high))
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

    /// Color de un valor aislado: azul bajo la referencia baja, rojo sobre la alta, neutro en el rango.
    static func color(for value: Int, low: Int, high: Int) -> Color {
        if value > high { return Tokens.Palette.high }
        if value < low { return Tokens.Palette.low }
        return .primary
    }

    /// Degradado vertical sobre el área del trazado con una transición de ±3 mg/dL en cada referencia.
    static func valueGradient(domain: ClosedRange<Int>, low: Int, high: Int) -> LinearGradient {
        LinearGradient(stops: gradientStops(domain: domain, low: low, high: high), startPoint: .bottom, endPoint: .top)
    }

    /// Paradas (fracción 0 = mínimo del dominio, 1 = máximo). Se recortan al dominio y quedan ordenadas.
    static func gradientStops(domain: ClosedRange<Int>, low: Int, high: Int, band: Double = 3) -> [Gradient.Stop] {
        let span = Double(max(1, domain.upperBound - domain.lowerBound))
        func fraction(_ value: Double) -> Double { min(1, max(0, (value - Double(domain.lowerBound)) / span)) }
        let neutral = Color.primary
        return [
            .init(color: Tokens.Palette.low, location: 0),
            .init(color: Tokens.Palette.low, location: fraction(Double(low) - band)),
            .init(color: neutral, location: fraction(Double(low) + band)),
            .init(color: neutral, location: fraction(Double(high) - band)),
            .init(color: Tokens.Palette.high, location: fraction(Double(high) + band)),
            .init(color: Tokens.Palette.high, location: 1),
        ]
    }
}
