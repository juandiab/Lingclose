import Charts
import LingoCore
import SwiftUI

/// Perfil por hora del día (tipo AGP): banda p5–p95 y p25–p75 como áreas neutras, mediana en línea, referencias del
/// rango discontinuas y zonas fuera del rango con un lavado tenue (ámbar arriba, azul abajo). Las medias horas sin
/// datos suficientes quedan abiertas.
struct HourlyProfileChart: View {
    let points: [HourlyProfilePoint]
    let configuration: ReportConfiguration

    var body: some View {
        let domain = Self.valueDomain(points: points, configuration: configuration)
        let low = Double(configuration.rangeLow)
        let high = Double(configuration.rangeHigh)
        Chart {
            RectangleMark(
                xStart: .value("Inicio", 0), xEnd: .value("Fin", 1_440),
                yStart: .value("Referencia alta", high), yEnd: .value("Máximo", domain.upperBound))
                .foregroundStyle(ReportPalette.highZone)
            RectangleMark(
                xStart: .value("Inicio", 0), xEnd: .value("Fin", 1_440),
                yStart: .value("Mínimo", domain.lowerBound), yEnd: .value("Referencia baja", low))
                .foregroundStyle(ReportPalette.lowZone)
            ForEach(points) { point in
                AreaMark(
                    x: .value("Hora", point.minute),
                    yStart: .value("P5", point.p5),
                    yEnd: .value("P95", point.p95),
                    series: .value("Banda", "exterior-\(point.run)"))
                    .foregroundStyle(ReportPalette.outerBand)
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                AreaMark(
                    x: .value("Hora", point.minute),
                    yStart: .value("P25", point.p25),
                    yEnd: .value("P75", point.p75),
                    series: .value("Banda", "interior-\(point.run)"))
                    .foregroundStyle(ReportPalette.innerBand)
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Referencia alta", high))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(ReportPalette.referenceStroke)
            RuleMark(y: .value("Referencia baja", low))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(ReportPalette.referenceStroke)
            ForEach(points) { point in
                LineMark(
                    x: .value("Hora", point.minute),
                    y: .value("Mediana", point.p50),
                    series: .value("Mediana", "mediana-\(point.run)"))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...1_440)
        .chartYScale(domain: domain)
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
        .accessibilityLabel(String(localized: "reports.profile.chart.a11y", defaultValue: "Perfil por hora del día"))
        .accessibilityValue(Self.spokenSummary(points))
    }

    /// Dominio vertical: incluye el rango de referencia y los percentiles extremos, en múltiplos de 20.
    static func valueDomain(points: [HourlyProfilePoint], configuration: ReportConfiguration) -> ClosedRange<Double> {
        let lowest = min(points.map(\.p5).min() ?? 100, Double(configuration.rangeLow))
        let highest = max(points.map(\.p95).max() ?? 160, Double(configuration.rangeHigh))
        let lower = max(0, ((lowest - 10) / 20).rounded(.down) * 20)
        let upper = ((highest + 10) / 20).rounded(.up) * 20
        return lower...upper
    }

    /// "Mediana entre 92 y 151 mg/dL; la más alta hacia las 2 p. m., la más baja hacia las 4 a. m."
    static func spokenSummary(_ points: [HourlyProfilePoint]) -> String {
        guard let lowest = points.min(by: { $0.p50 < $1.p50 }), let highest = points.max(by: { $0.p50 < $1.p50 }) else {
            return String(localized: "reports.profile.chart.empty", defaultValue: "Sin datos suficientes")
        }
        return String(
            localized: "reports.profile.chart.summary",
            defaultValue: "Mediana entre \(Int(lowest.p50.rounded())) y \(Int(highest.p50.rounded())) miligramos por decilitro; la más alta hacia las \(ReportFormat.clock(minute: highest.minute)), la más baja hacia las \(ReportFormat.clock(minute: lowest.minute)).")
    }
}
