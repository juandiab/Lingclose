import Foundation
import LingoCore
import Testing
@testable import LingoScan

struct ReportsContentTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let bogota = TimeZone(identifier: "America/Bogota")!

    private func bundle(_ preset: ReportPeriod.Preset = .days14) async throws -> ReportBundle {
        let source = PreviewReportsDataSource(data: PreviewData(now: Self.now))
        let period = ReportPeriod.preset(preset, endingAt: UTCInstant(Self.now), timeZone: Self.bogota)
        let readings = try await source.readings(in: period.dataRange)
        let events = try await source.events(in: period.dataRange)
        return ReportBuilder.build(readings: readings, events: events, period: period,
                                   configuration: ReportConfiguration(range: 70...140))
    }

    @Test func previewHistoryIsSyntheticAndCoversFourteenDays() async throws {
        let data = PreviewData(now: Self.now)
        let history = data.reportHistory()
        #expect(history.readings.allSatisfy { $0.synthetic })
        #expect(history.events.allSatisfy { $0.synthetic })
        #expect(history.events.contains { $0.kind == .exercise })
        let oldest = try #require(history.readings.first?.measuredAt.date)
        #expect(Self.now.timeIntervalSince(oldest) > 13 * 86_400)
        // El historial termina antes de la sesión actual (no se solapa con Hoy).
        let newest = try #require(history.readings.last?.measuredAt)
        #expect(newest < data.session.activatedAt)
    }

    @Test func profilePointsSplitIntoRunsAtMissingBins() async throws {
        let bundle = try await bundle()
        let points = HourlyProfilePoint.points(from: bundle.hourlyProfile)
        #expect(points.count == bundle.hourlyProfile.reportedBins)
        #expect(points.allSatisfy { $0.p5 <= $0.p25 && $0.p25 <= $0.p50 && $0.p50 <= $0.p75 && $0.p75 <= $0.p95 })
        // Un tramo nuevo empieza tras cada media hora sin percentiles.
        for (previous, next) in zip(points, points.dropFirst()) {
            #expect(next.run == (next.id == previous.id + 1 ? previous.run : previous.run + 1))
        }
    }

    @Test func overlayHighlightsOnlyTheLastDayAndBreaksAtGaps() async throws {
        let bundle = try await bundle()
        let content = ReportContent(preset: .days14, bundle: bundle)
        let latest = try #require(bundle.dailyOverlay.days.last?.summary.day.date)
        #expect(content.overlayCompact.contains { $0.isLatest })
        #expect(content.overlayCompact.filter(\.isLatest).allSatisfy { $0.day == latest })
        // 15 min en la card: como mucho 96 puntos por día; 5 min en el detalle hasta 14 días.
        let perDay = Dictionary(grouping: content.overlayCompact, by: \.day).mapValues(\.count)
        #expect(perDay.values.allSatisfy { $0 <= 96 })
        #expect(content.overlayDetailed.count > content.overlayCompact.count)
        // El hueco de 3 h del historial parte su día en más de un tramo.
        let series = Set(content.overlayDetailed.map(\.series))
        #expect(series.count > Set(content.overlayDetailed.map(\.day)).count)
    }

    @Test func mealCurvesStartAtTheMealAndLastThreeHours() async throws {
        let bundle = try await bundle()
        let content = ReportContent(preset: .days14, bundle: bundle)
        let measured = bundle.meals.meals.filter { $0.response != nil }
        #expect(!measured.isEmpty)
        for meal in measured {
            let curve = try #require(content.mealCurves[meal.at])
            #expect(!curve.isEmpty)
            #expect(curve.allSatisfy { (0...ReportContent.mealCurveMinutes).contains($0.minute) })
        }
    }

    @Test func weeklyMetricsJudgeDirection() async throws {
        let bundle = try await bundle()
        let report = bundle.weeklyComparison
        let current = try #require(report.current)
        let previous = try #require(report.previous)
        let deltas = try #require(report.deltas)
        let tir = try #require(WeeklyMetric.timeInRange.delta(
            current: current, previous: previous, deltas: deltas, configuration: bundle.configuration))
        if let change = deltas.timeInRange, abs(change) >= 0.01 {
            #expect(tir.judgment == (change > 0 ? .better : .worse))
        } else {
            #expect(tir.judgment == .neutral)
        }
        let meals = try #require(WeeklyMetric.meals.delta(
            current: current, previous: previous, deltas: deltas, configuration: bundle.configuration))
        #expect(meals.judgment == .neutral)
    }

    @Test func formatsSignedValuesWithoutRed() {
        #expect(ReportFormat.signed(12.4) == "+12")
        #expect(ReportFormat.signed(-5.6) == "−6")
        #expect(ReportFormat.signed(0.3) == "0")
        #expect(ReportDelta.direction(0.5, threshold: 1) == .flat)
    }

    @Test func bandSharesAddUpToTheWhole() async throws {
        let bundle = try await bundle()
        let shares = ReportBandShare.shares(bundle.summary.stats)
        #expect(shares.map(\.band) == [.low, .inRange, .high, .veryHigh])
        #expect(abs(shares.map(\.fraction).reduce(0, +) - 1) < 0.001)
    }

    @Test func snapshotExportWritesDecodableJSON() async throws {
        let bundle = try await bundle(.days7)
        let export = ReportSnapshotExport(bundle: bundle)
        #expect(export.fileName.hasPrefix("lingclose-reporte-"))
        #expect(export.fileName.hasSuffix(".json"))
        let url = try export.writeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try ReportSnapshot.decode(Data(contentsOf: url))
        #expect(decoded.period.days == 7)
        let text = try #require(String(data: try export.jsonData(), encoding: .utf8))
        #expect(!text.contains("synthetic-"))
    }

    @MainActor
    @Test func summaryImageRendersAsPNG() async throws {
        let bundle = try await bundle(.days7)
        let data = try ReportSummaryImageExport(bundle: bundle, isSynthetic: true).pngData()
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(data.count > 10_000)
    }
}
