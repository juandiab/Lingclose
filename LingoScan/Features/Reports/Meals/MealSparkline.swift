import Charts
import LingoCore
import SwiftUI

/// Mini-curva de 3 h tras una comida: línea base punteada, referencia alta tenue y la curva en verde si no pasó de
/// la referencia alta o en ámbar si la pasó. Decorativa para VoiceOver (la fila ya dice subida, pico y retorno).
struct MealSparkline: View {
    let points: [MealSparkPoint]
    let baseline: Double?
    let configuration: ReportConfiguration

    var body: some View {
        let peak = points.map(\.value).max() ?? 0
        let color = peak > configuration.rangeHigh ? Tokens.Palette.outOfRange : ReportPalette.inRange
        let values = points.map { Double($0.value) } + [baseline].compactMap(\.self)
        let lower = (values.min() ?? 80) - 8
        let upper = max(values.max() ?? 140, Double(configuration.rangeHigh)) + 8
        Chart {
            RuleMark(y: .value("Referencia alta", configuration.rangeHigh))
                .foregroundStyle(Tokens.Palette.outOfRange.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [2, 3]))
            if let baseline {
                RuleMark(y: .value("Línea base", baseline))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [1, 2]))
            }
            ForEach(points) { point in
                LineMark(x: .value("Minuto", point.minute), y: .value("mg/dL", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...ReportContent.mealCurveMinutes)
        .chartYScale(domain: lower...upper)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
