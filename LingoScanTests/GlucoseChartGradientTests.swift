import SwiftUI
import Testing
@testable import LingoScan

/// Color de la curva por valor: azul bajo la referencia baja, neutro en el rango, rojo sobre la alta.
struct GlucoseChartGradientTests {
    private func segment(_ values: [Int]) -> GlucoseSegment {
        GlucoseSegment(id: 0, points: values.enumerated().map { index, value in
            GlucosePoint(id: "p\(index)", sessionID: "s", lifeCount: index, date: Date(timeIntervalSince1970: Double(index) * 60), value: value)
        })
    }

    @Test func isolatedPointColorMatchesTheReferences() {
        #expect(GlucoseChart.color(for: 150, low: 70, high: 140) == Tokens.Palette.high)
        #expect(GlucoseChart.color(for: 60, low: 70, high: 140) == Tokens.Palette.low)
        #expect(GlucoseChart.color(for: 100, low: 70, high: 140) == .primary)
    }

    @Test func runsSplitAtInterpolatedCrossings() {
        // 100 → 160 cruza la alta (140) a los 40 s; 160 → 60 cruza la alta y la baja.
        let runs = GlucoseColorRun.runs(for: segment([100, 160, 60]), low: 70, high: 140)
        #expect(runs.map(\.band) == [.inRange, .high, .inRange, .low])
        #expect(runs[0].vertices.map(\.value) == [100, 140])
        #expect(runs[0].vertices.last?.date == Date(timeIntervalSince1970: 40))
        #expect(runs[1].vertices.map(\.value) == [140, 160, 140])
        #expect(runs[2].vertices.map(\.value) == [140, 70])
        #expect(runs[3].vertices.map(\.value) == [70, 60])
        // Cada cruce pertenece a los dos trozos: la línea no se corta.
        for (before, after) in zip(runs, runs.dropFirst()) {
            #expect(before.vertices.last == after.vertices.first)
        }
        #expect(Set(runs.map(\.id)).count == runs.count)
    }

    @Test func runsKeepASingleColorWhenNothingCrosses() {
        let inRange = GlucoseColorRun.runs(for: segment([90, 120, 100]), low: 70, high: 140)
        #expect(inRange.count == 1 && inRange[0].band == .inRange && inRange[0].vertices.count == 3)
        let high = GlucoseColorRun.runs(for: segment([150, 180]), low: 70, high: 140)
        #expect(high.count == 1 && high[0].band == .high)
        #expect(GlucoseColorRun.runs(for: segment([60]), low: 70, high: 140).first?.band == .low)
        #expect(GlucoseColorRun.runs(for: GlucoseSegment(id: 1, points: []), low: 70, high: 140).isEmpty)
    }

    @Test func aValueExactlyOnAReferenceChangesColorAtThatPoint() {
        let runs = GlucoseColorRun.runs(for: segment([120, 140, 150]), low: 70, high: 140)
        #expect(runs.map(\.band) == [.inRange, .high])
        #expect(runs[0].vertices.map(\.value) == [120, 140])
        #expect(runs[1].vertices.map(\.value) == [140, 150])
    }
}
