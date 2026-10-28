import SwiftUI
import Testing
@testable import LingoScan

/// Degradado por valor de la curva: azul bajo la referencia baja, neutro en el rango, rojo sobre la alta.
struct GlucoseChartGradientTests {
    @Test func stopsFollowTheReferencesWithinTheDomain() {
        let stops = GlucoseChart.gradientStops(domain: 0...200, low: 70, high: 140)
        #expect(stops.count == 6)
        #expect(stops.map(\.location) == [0, 0.335, 0.365, 0.685, 0.715, 1])
        #expect(stops.map(\.location) == stops.map(\.location).sorted(), "siempre ordenadas")
        #expect(stops[0].color == Tokens.Palette.low && stops[5].color == Tokens.Palette.high)
    }

    @Test func stopsAreClampedWhenAReferenceFallsOutsideTheDomain() {
        let stops = GlucoseChart.gradientStops(domain: 100...200, low: 70, high: 140)
        #expect(stops[1].location == 0 && stops[2].location == 0, "la baja queda fuera: sin tramo azul")
        #expect(stops.allSatisfy { (0...1).contains($0.location) })
    }

    @Test func isolatedPointColorMatchesTheReferences() {
        #expect(GlucoseChart.color(for: 150, low: 70, high: 140) == Tokens.Palette.high)
        #expect(GlucoseChart.color(for: 60, low: 70, high: 140) == Tokens.Palette.low)
        #expect(GlucoseChart.color(for: 100, low: 70, high: 140) == .primary)
    }

    @Test func segmentStopsUseTheSegmentRangeAndDropClampedEdges() {
        func segment(_ values: [Int]) -> GlucoseSegment {
            GlucoseSegment(id: 0, points: values.enumerated().map { index, value in
                GlucosePoint(id: "p\(index)", sessionID: "s", lifeCount: index, date: Date(timeIntervalSince1970: Double(index) * 60), value: value)
            })
        }
        // 100…160: la baja (70) queda fuera; el borde inferior es neutro, no azul.
        let stops = GlucoseChart.segmentStops(segment([100, 160]), low: 70, high: 140)
        #expect(stops.first?.color == .primary)
        #expect(stops.last?.color == Tokens.Palette.high)
        #expect(stops.map(\.location) == stops.map(\.location).sorted())
        // Todo en rango: sin rojo ni azul.
        let inRange = GlucoseChart.segmentStops(segment([90, 120]), low: 70, high: 140)
        #expect(inRange.allSatisfy { $0.color == .primary })
        // Un solo punto: color único según su valor.
        #expect(GlucoseChart.segmentStops(segment([60]), low: 70, high: 140).allSatisfy { $0.color == Tokens.Palette.low })
    }
}
