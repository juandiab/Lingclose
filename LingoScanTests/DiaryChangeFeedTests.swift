import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// T-32: borrado sin abortar la lista, aviso de cambios del diario e identidades estables.
@MainActor
struct DiaryChangeFeedTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func makeDiary(store: any DiaryStore, feed: DiaryChangeFeed) -> DiaryViewModel {
        DiaryViewModel(store: store, changes: feed, calendar: Self.calendar, now: { Self.now })
    }

    private func mealDraft(minutesAgo: Double = 30) -> DiaryDraft {
        var draft = DiaryDraft(now: Self.now.addingTimeInterval(-minutesAgo * 60))
        draft.kind = .meal
        draft.carbsText = "40"
        return draft
    }

    private func event(_ id: String, hoursAgo: Double) -> DiaryEvent {
        DiaryEvent(
            eventID: id, kind: .note, at: UTCInstant(Self.now.addingTimeInterval(-hoursAgo * 3600)), tz: "UTC",
            text: id, createdAt: UTCInstant(Self.now), updatedAt: UTCInstant(Self.now), editID: "e-\(id)",
            editedByAppID: "x", synthetic: false)
    }

    /// Espera acotada en el actor principal (los modelos son `@MainActor`).
    private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: Señal

    @Test func deleteNotifiesTheFeedWithItsOrigin() async throws {
        let feed = DiaryChangeFeed()
        let model = makeDiary(store: InMemoryDiaryStore(), feed: feed)
        #expect(await model.save(mealDraft(), editing: nil))
        let saved = try #require(model.days.first?.events.first)

        var changes = feed.changes().makeAsyncIterator()
        await model.delete(saved)

        let change = await changes.next()
        #expect(change == DiaryChangeFeed.Change(origin: ObjectIdentifier(model)))
        #expect(model.days.isEmpty)
    }

    @Test func saveNotifiesTheFeed() async {
        let feed = DiaryChangeFeed()
        let model = makeDiary(store: InMemoryDiaryStore(), feed: feed)
        var changes = feed.changes().makeAsyncIterator()
        #expect(await model.save(mealDraft(), editing: nil))
        #expect(await changes.next() != nil)
    }

    @Test func failedDeleteDoesNotNotify() async throws {
        let feed = DiaryChangeFeed()
        let store = InMemoryDiaryStore()
        let model = makeDiary(store: store, feed: feed)
        #expect(await model.save(mealDraft(), editing: nil))
        let saved = try #require(model.days.first?.events.first)
        var changes = feed.changes().makeAsyncIterator()
        await store.setFailNextSave(true)
        await model.delete(saved)
        feed.notify()   // centinela: el primer aviso recibido debe ser este, sin origen
        #expect(await changes.next() == DiaryChangeFeed.Change(origin: nil))
        #expect(model.failure == .saveFailed)
    }

    // MARK: Borrado tras cerrar el diálogo

    @Test func confirmedDeletionWaitsUntilTheDialogIsClosed() async throws {
        let store = InMemoryDiaryStore()
        let model = makeDiary(store: store, feed: DiaryChangeFeed())
        #expect(await model.save(mealDraft(), editing: nil))
        let saved = try #require(model.days.first?.events.first)

        model.pendingDeletion = saved            // deslizar → diálogo
        model.confirmDeletion(saved)             // "Borrar" en el diálogo
        #expect(!model.hasDeletionReadyToCommit) // el diálogo sigue presentado: la lista no cambia
        await model.commitConfirmedDeletion()
        #expect(model.days.first?.events.first?.eventID == saved.eventID)

        model.isConfirmingDeletion = false       // el diálogo terminó de cerrarse
        #expect(model.hasDeletionReadyToCommit)
        await model.commitConfirmedDeletion()
        #expect(model.days.isEmpty)
        #expect(!model.hasDeletionReadyToCommit)
        #expect(await store.versions(of: saved.eventID).last?.deleted == true)
    }

    @Test func cancellingTheDialogDeletesNothing() async throws {
        let store = InMemoryDiaryStore()
        let model = makeDiary(store: store, feed: DiaryChangeFeed())
        #expect(await model.save(mealDraft(), editing: nil))
        let saved = try #require(model.days.first?.events.first)
        model.pendingDeletion = saved
        model.isConfirmingDeletion = false
        #expect(!model.hasDeletionReadyToCommit)
        await model.commitConfirmedDeletion()
        #expect(await store.versions(of: saved.eventID).count == 1)
        #expect(!model.days.isEmpty)
    }

    // MARK: Otras pantallas recargan

    @Test func anotherDiaryInstanceReloadsWhenOneDeletes() async throws {
        let feed = DiaryChangeFeed()
        let store = InMemoryDiaryStore()
        let tab = makeDiary(store: store, feed: feed)
        let entries = makeDiary(store: store, feed: feed)
        #expect(await entries.save(mealDraft(), editing: nil))
        await tab.load()
        let saved = try #require(tab.days.first?.events.first)

        let observing = Task { await tab.observeChanges() }
        defer { observing.cancel() }
        let ready1 = await waitUntil { feed.subscriberCount == 1 }
        #expect(ready1)

        await entries.delete(saved)
        let ready2 = await waitUntil { tab.days.isEmpty }
        #expect(ready2)
    }

    @Test func todayReloadsMarksWhenTheDiaryChanges() async throws {
        let data = PreviewData(now: Self.now)
        let feed = DiaryChangeFeed()
        let today = TodayViewModel(dataSource: data, sensorSource: data, diaryChanges: feed, clock: { Self.now })
        await today.refresh()
        let before = today.marks.count
        let mealAt = Self.now.addingTimeInterval(-30 * 60)

        let observing = Task { await today.observe() }
        defer { observing.cancel() }
        let ready3 = await waitUntil { feed.subscriberCount == 1 }
        #expect(ready3)

        // El Diario (otra instancia, mismo almacén y mismo aviso) guarda: la marca aparece sin recargar Hoy a mano.
        let diary = makeDiary(store: today.diaryStore, feed: feed)
        #expect(await diary.save(mealDraft(), editing: nil))
        let ready4 = await waitUntil { today.marks.count == before + 1 }
        #expect(ready4)
        #expect(today.marks.contains { $0.kind == .meal && $0.date == mealAt })

        // Y al borrarla desde el Diario, desaparece de la curva.
        let saved = try #require(diary.days.flatMap(\.events).first { $0.at.date == mealAt })
        await diary.delete(saved)
        let ready5 = await waitUntil { today.marks.count == before }
        #expect(ready5)
        #expect(!today.marks.contains { $0.id == saved.eventID })
    }

    @Test func todayIgnoresItsOwnNotificationButRefreshes() async {
        let data = PreviewData(now: Self.now)
        let feed = DiaryChangeFeed()
        let today = TodayViewModel(dataSource: data, sensorSource: data, diaryChanges: feed, clock: { Self.now })
        var changes = feed.changes().makeAsyncIterator()
        await today.diaryDidChange()
        #expect(today.hasLoaded)
        #expect(await changes.next() == DiaryChangeFeed.Change(origin: ObjectIdentifier(today)))
    }

    // MARK: Identidades estables

    @Test func groupedDaysHaveStableCalendarDayIdentities() {
        let events = [event("a", hoursAgo: 1), event("b", hoursAgo: 2), event("c", hoursAgo: 30), event("d", hoursAgo: 31)]
        let first = DiaryViewModel.group(events, calendar: Self.calendar)
        let again = DiaryViewModel.group(events.reversed(), calendar: Self.calendar)
        #expect(first == again)
        #expect(Set(first.map(\.id)).count == first.count)
        // 1_800_000_000 = 2027-01-15 08:00 UTC.
        #expect(first.map(\.id) == ["2027-01-15", "2027-01-14"])
        #expect(first[0].events.map(\.eventID) == ["a", "b"])

        // Borrar una fila no cambia la identidad de su sección ni la de las demás.
        let afterDelete = DiaryViewModel.group(events.filter { $0.eventID != "a" }, calendar: Self.calendar)
        #expect(afterDelete.map(\.id) == first.map(\.id))
        #expect(afterDelete[0].events.map(\.eventID) == ["b"])

        // Vaciar un día quita solo esa sección; la otra conserva su identidad.
        let dayGone = DiaryViewModel.group(events.filter { $0.eventID != "c" && $0.eventID != "d" }, calendar: Self.calendar)
        #expect(dayGone.map(\.id) == ["2027-01-15"])
    }

    @Test func reloadWithTheSameDataKeepsTheSameDays() async {
        let store = InMemoryDiaryStore(events: [event("a", hoursAgo: 1), event("b", hoursAgo: 30)])
        let model = makeDiary(store: store, feed: DiaryChangeFeed())
        await model.load()
        let days = model.days
        await model.load()
        #expect(model.days == days)
    }
}
