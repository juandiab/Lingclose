import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Cursor sobre la curva, navegación por día, registro del día y picos (T-11b; ventana desplazable).
@MainActor
struct TodayInteractionTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func makeModel() -> (TodayViewModel, PreviewData) {
        let data = PreviewData(now: Self.now)
        let model = TodayViewModel(dataSource: data, sensorSource: data, calendar: Self.calendar, clock: { Self.now })
        return (model, data)
    }

    // MARK: Lectura más cercana al arrastre

    @Test func nearestReadingToTheFingerIsTheClosestInTime() async throws {
        let (model, _) = makeModel()
        await model.refresh()
        let target = try #require(model.points.last)
        // 20 s después de la última lectura: sigue siendo esa lectura.
        let hit = try #require(model.nearestPoint(to: target.date.addingTimeInterval(20)))
        #expect(hit.id == target.id)
        // Entre dos lecturas contiguas gana la más cercana.
        let middle = try #require(model.points.dropFirst(10).first)
        let next = try #require(model.points.dropFirst(11).first)
        #expect(model.nearestPoint(to: middle.date.addingTimeInterval(10))?.id == middle.id)
        #expect(model.nearestPoint(to: next.date.addingTimeInterval(-10))?.id == next.id)
    }

    @Test func draggingOverAGapReturnsNil() async throws {
        let (model, _) = makeModel()
        model.setVisibleLength(TodayPeriod.twelveHours.duration)
        await model.refresh()
        let gap = try #require(model.gaps.first)
        let middle = gap.start.addingTimeInterval(gap.duration / 2)
        #expect(model.nearestPoint(to: middle) == nil)
        #expect(model.readoutText(at: middle).contains(middle.formatted(date: .omitted, time: .shortened)))
        // Fuera de los datos (después de la última lectura) tampoco hay lectura.
        let last = try #require(model.points.last)
        #expect(model.nearestPoint(to: last.date.addingTimeInterval(5 * 60)) == nil)
    }

    @Test func readoutTextNamesValueAndTime() async throws {
        let (model, _) = makeModel()
        await model.refresh()
        let point = try #require(model.points.last)
        let text = model.readoutText(at: point.date)
        #expect(text.contains("\(point.value)"))
        #expect(text.contains("mg/dL"))
    }

    // MARK: Navegación por día

    @Test func dayNavigationMovesTheVisibleWindowByOneDayKeepingItsLength() async throws {
        let (model, _) = makeModel()
        await model.refresh()
        let length = model.visibleLength
        #expect(model.isToday && !model.canGoForward && model.isLive)
        model.goForward()
        #expect(model.visibleEnd == Self.now, "› no pasa de hoy")

        model.goBack()
        await model.settle()
        let yesterday = Self.calendar.startOfDay(for: Self.now.addingTimeInterval(-86_400))
        #expect(model.shownDay == yesterday && model.canGoForward && !model.isLive)
        #expect(close(model.visibleEnd, Self.now.addingTimeInterval(-86_400)))
        #expect(model.visibleLength == length)
        #expect(close(model.windowEnd, model.visibleEnd) && close(model.windowStart, model.visibleStart))
        #expect(model.visiblePoints.allSatisfy { $0.date >= model.windowStart && $0.date <= model.windowEnd })
        #expect(!model.visiblePoints.isEmpty)

        model.goForward()
        await model.settle()
        #expect(model.isToday && model.isLive)
        #expect(model.windowEnd == Self.now)
    }

    @Test func selectingADateEndsAtTheSameClockTimeAndNeverGoesIntoTheFuture() {
        let (model, _) = makeModel()
        model.select(day: Self.now.addingTimeInterval(-3 * 86_400))
        #expect(close(model.visibleEnd, Self.now.addingTimeInterval(-3 * 86_400)))
        #expect(model.shownDay == Self.calendar.startOfDay(for: Self.now.addingTimeInterval(-3 * 86_400)))
        model.select(day: Self.now.addingTimeInterval(5 * 86_400))
        #expect(model.visibleEnd == Self.now)
        #expect(model.isToday && model.isLive)
    }

    // MARK: Registro del día

    @Test func dayEntryCountCoversTheWholeDayNotJustTheVisibleWindow() async throws {
        let (model, data) = makeModel()
        model.setVisibleLength(TodayPeriod.sixHours.duration)
        await model.refresh()
        #expect(model.entriesDay == Self.calendar.startOfDay(for: Self.now))
        let dayStart = Self.calendar.startOfDay(for: Self.now)
        let expected = data.events.filter { $0.at.date >= dayStart && $0.at.date < dayStart.addingTimeInterval(86_400) }.count
        #expect(model.dayEntryCount == expected)
        #expect(model.dayEntryCount >= model.marks.filter { $0.date >= dayStart }.count)
    }

    // MARK: Picos

    @Test func spikesAreComputedOverTheVisiblePointsAndFollowTheThreshold() async {
        let (model, _) = makeModel()
        model.setVisibleLength(TodayPeriod.twentyFourHours.duration)
        await model.refresh()
        #expect(!model.spikes.isEmpty)
        #expect(model.spikes.allSatisfy { $0.start >= model.windowStart && $0.end <= model.windowEnd })
        #expect(model.spikes.allSatisfy { $0.peakValue > model.referenceHigh && $0.start <= $0.peakAt && $0.peakAt <= $0.end })
        let before = model.spikes.count
        model.referenceHigh = 400
        #expect(model.spikes.isEmpty)
        model.referenceHigh = 140
        #expect(model.spikes.count == before)
    }

    @Test func referenceLinesAreNormalized() {
        #expect(ReferenceLines.normalized(low: 70, high: 140) == (70, 140))
        #expect(ReferenceLines.normalized(low: 200, high: 100).high == 210)
        #expect(ReferenceLines.normalized(low: 0, high: 9_999) == (40, 400))
    }

    @Test func chartDomainKeepsRoomBelowTheLowLine() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.chartValueDomain.lowerBound <= model.referenceLow - 60)
        #expect(model.chartValueDomain.upperBound >= 220)
    }
}

/// Fechas iguales salvo redondeo de coma flotante.
private func close(_ lhs: Date, _ rhs: Date) -> Bool {
    abs(lhs.timeIntervalSince(rhs)) < 0.001
}
