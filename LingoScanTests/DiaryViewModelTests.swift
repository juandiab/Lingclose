import Foundation
import Testing
import LingoCore
import os
@testable import LingoScan

/// Generador de ids deterministas para las pruebas.
final class IDSequence: Sendable {
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    func next() -> String {
        counter.withLock { value in
            value += 1
            return "id-\(value)"
        }
    }
}

@MainActor
struct DiaryViewModelTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func makeModel(store: any DiaryStore = InMemoryDiaryStore(), ids: IDSequence = IDSequence()) -> DiaryViewModel {
        DiaryViewModel(store: store, calendar: Self.calendar, now: { Self.now }, newID: { ids.next() })
    }

    private func mealDraft(carbs: String = "45") -> DiaryDraft {
        var draft = DiaryDraft(now: Self.now)
        draft.kind = .meal
        draft.carbsText = carbs
        draft.text = "  Arepa  "
        return draft
    }

    // MARK: Alta

    @Test func addingAMealCreatesTheFirstEditWithoutParent() async throws {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        #expect(await model.save(mealDraft(carbs: "45,5"), editing: nil))
        let saved = try #require(await store.history.first)
        #expect(saved.kind == .meal)
        #expect(saved.carbsG == 45.5)
        #expect(saved.text == "Arepa")
        #expect(saved.parentEditID == nil)
        #expect(saved.revision == 1)
        #expect(saved.editID != saved.eventID)
        #expect(saved.editedByAppID == DiaryViewModel.appID)
        #expect(!saved.deleted && !saved.synthetic)
        #expect(saved.at == UTCInstant(Self.now))
        #expect(model.days.flatMap(\.events).map(\.eventID) == [saved.eventID])
    }

    @Test func twoTapAddNeedsNoTextForAMeal() async {
        let model = makeModel()
        model.beginAdd()
        let editor = model.editor
        #expect(editor?.draft.kind == .meal)
        #expect(editor?.draft.at == Self.now)
        #expect(editor?.draft.isValid == true)
        #expect(await model.save(editor?.draft ?? DiaryDraft(now: Self.now), editing: nil))
        #expect(model.editor == nil)
    }

    @Test func validationRules() {
        var draft = DiaryDraft(now: Self.now)
        #expect(draft.isValid)
        draft.carbsText = "abc"
        #expect(draft.problem == .carbsOutOfRange)
        draft.carbsText = "1500"
        #expect(draft.problem == .carbsOutOfRange)
        draft.carbsText = ""
        draft.kind = .exercise
        #expect(draft.problem == .durationMissing)
        draft.durationText = "30"
        #expect(draft.isValid)
        #expect(draft.durationMin == 30)
        #expect(draft.carbsG == nil)
        draft.kind = .note
        #expect(draft.problem == .noteIsEmpty)
        draft.text = " hola "
        #expect(draft.isValid)
    }

    @Test func invalidDraftIsNotSaved() async {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        var draft = DiaryDraft(now: Self.now)
        draft.kind = .note
        #expect(await model.save(draft, editing: nil) == false)
        #expect(await store.history.isEmpty)
    }

    // MARK: Edición y borrado con linaje

    @Test func editCreatesNewEditIDWithParentAndKeepsIdentity() async throws {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        await model.save(mealDraft(), editing: nil)
        let original = try #require(await store.history.first)

        var edited = DiaryDraft(event: original)
        edited.carbsText = "60"
        #expect(await model.save(edited, editing: original))

        let versions = await store.versions(of: original.eventID)
        #expect(versions.count == 2)
        let second = versions[1]
        #expect(second.eventID == original.eventID)
        #expect(second.editID != original.editID)
        #expect(second.parentEditID == original.editID)
        #expect(second.revision == 2)
        #expect(second.carbsG == 60)
        #expect(second.createdAt == original.createdAt)
        #expect(model.days.flatMap(\.events).first?.carbsG == 60)
    }

    @Test func deleteWritesATombstoneChainedToTheLastEdit() async throws {
        let store = InMemoryDiaryStore()
        let model = makeModel(store: store)
        await model.save(mealDraft(), editing: nil)
        let original = try #require(await store.history.first)
        var edited = DiaryDraft(event: original)
        edited.carbsText = "50"
        await model.save(edited, editing: original)
        let latest = try #require(model.days.flatMap(\.events).first)

        await model.delete(latest)

        let versions = await store.versions(of: original.eventID)
        #expect(versions.count == 3)
        let tombstone = versions[2]
        #expect(tombstone.deleted)
        #expect(tombstone.parentEditID == latest.editID)
        #expect(tombstone.editID != latest.editID)
        #expect(tombstone.revision == 3)
        #expect(model.days.isEmpty)
        #expect(model.isEmpty)
        // Cadena completa: creación ← edición ← tombstone.
        #expect(versions.map(\.parentEditID) == [nil, versions[0].editID, versions[1].editID])
    }

    @Test func lineageIsPersistedInTheRealStore() async throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "diary-\(UUID().uuidString).sqlite").path
        let sqlite = try SQLiteStore(path: path)
        let model = makeModel(store: SQLiteDiaryStore(store: sqlite))
        await model.save(mealDraft(), editing: nil)
        let created = try #require(model.days.flatMap(\.events).first)
        var edited = DiaryDraft(event: created)
        edited.text = "Arepa con huevo"
        await model.save(edited, editing: created)
        let second = try #require(model.days.flatMap(\.events).first)
        await model.delete(second)

        let all = try await sqlite.events(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 4_000_000_000), includeDeleted: true)
        let tombstone = try #require(all.first)
        #expect(all.count == 1 && tombstone.deleted)
        let ancestors = try #require(try await sqlite.editAncestors(of: tombstone))
        #expect(ancestors.map(\.editID) == [second.editID, created.editID])
        #expect(ancestors.last?.parentEditID == nil)
        #expect(try await sqlite.events(in: UTCInstant(epochSeconds: 0)...UTCInstant(epochSeconds: 4_000_000_000)).isEmpty)
    }

    // MARK: Sintéticos, agrupación y fallos

    @Test func syntheticPreviewEventsAreShownButNotModifiable() async throws {
        let data = PreviewData(now: Self.now)
        let synthetic = try #require(data.events.first)
        #expect(synthetic.synthetic)
        let store = InMemoryDiaryStore(events: data.events)
        let model = makeModel(store: store)
        await model.load()
        #expect(!model.days.isEmpty)
        #expect(!model.canModify(synthetic))
        model.beginEdit(synthetic)
        #expect(model.editor == nil)
        await model.delete(synthetic)
        #expect(await store.history.count == data.events.count)
    }

    @Test func daysAreGroupedNewestFirst() {
        func event(_ id: String, hoursAgo: Double) -> DiaryEvent {
            DiaryEvent(
                eventID: id, kind: .note, at: UTCInstant(Self.now.addingTimeInterval(-hoursAgo * 3600)), tz: "UTC",
                text: id, createdAt: UTCInstant(Self.now), updatedAt: UTCInstant(Self.now), editID: "e-\(id)",
                editedByAppID: "x", synthetic: false)
        }
        let days = DiaryViewModel.group([event("a", hoursAgo: 1), event("b", hoursAgo: 2), event("c", hoursAgo: 30)], calendar: Self.calendar)
        #expect(days.count == 2)
        #expect(days[0].start > days[1].start)
        #expect(days[0].events.map(\.eventID) == ["a", "b"])
    }

    @Test func saveFailureKeepsTheEditorOpen() async {
        let store = InMemoryDiaryStore()
        await store.setFailNextSave(true)
        let model = makeModel(store: store)
        model.beginAdd()
        #expect(await model.save(mealDraft(), editing: nil) == false)
        #expect(model.failure == .saveFailed)
        #expect(model.editor != nil)
    }
}
