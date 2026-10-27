import Accessibility
import SwiftUI

/// Descriptor de accesibilidad de la curva: resumen, rangos y serie (submuestreada) para VoiceOver.
struct GlucoseChartDescriptor: AXChartDescriptorRepresentable {
    let points: [GlucosePoint]
    let start: Date
    let end: Date
    let valueDomain: ClosedRange<Int>
    let periodTitle: String
    var referenceLow = ReferenceLines.defaultLow
    var referenceHigh = ReferenceLines.defaultHigh

    /// Máximo de puntos que se entregan a VoiceOver.
    private static let maxPoints = 120

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "today.chart.axis.time", defaultValue: "Hora"),
            range: start.timeIntervalSince1970...end.timeIntervalSince1970,
            gridlinePositions: []
        ) { seconds in
            Date(timeIntervalSince1970: seconds).formatted(date: .omitted, time: .shortened)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "mg/dL",
            range: Double(valueDomain.lowerBound)...Double(valueDomain.upperBound),
            gridlinePositions: [Double(referenceLow), Double(referenceHigh)]
        ) { value in
            String(localized: "today.chart.axis.value", defaultValue: "\(Int(value)) miligramos por decilitro")
        }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "today.chart.series", defaultValue: "Glucosa"),
            isContinuous: false,
            dataPoints: sampled.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: Double($0.value)) }
        )
        return AXChartDescriptor(
            title: String(localized: "today.chart.title", defaultValue: "Glucosa, \(periodTitle)"),
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    private var sampled: [GlucosePoint] {
        guard points.count > Self.maxPoints else { return points }
        let step = Double(points.count - 1) / Double(Self.maxPoints - 1)
        return (0..<Self.maxPoints).map { points[Int((Double($0) * step).rounded())] }
    }

    private var summary: String {
        guard let minimum = points.map(\.value).min(),
              let maximum = points.map(\.value).max(),
              let last = points.last
        else {
            return String(localized: "today.chart.summary.empty", defaultValue: "Sin lecturas válidas en este período.")
        }
        return String(
            localized: "today.chart.summary",
            defaultValue: "Mínimo \(minimum), máximo \(maximum), último \(last.value) miligramos por decilitro. Los huecos no se interpolan."
        )
    }
}
