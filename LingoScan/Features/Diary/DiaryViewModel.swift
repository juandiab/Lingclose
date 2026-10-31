import Foundation
import LingoCore
import Observation

/// Diario de comidas, ejercicio y notas. Cada guardado crea una edición nueva (`edit_id`) cuyo
/// `parent_edit_id` es la edición anterior; el borrado es un tombstone con el mismo linaje (contrato §5.3).
@MainActor
@Observable
final class DiaryViewModel {
    enum Failure: Equatable {
        case loadFailed
        case saveFailed
    }

    static let appID = "com.otalvaro.lingoscan"
    /// Cuánto hacia atrás se muestra el diario.
    static let lookback: TimeInterval = 60 * 86_400

    private(set) var days: [DiaryDay] = []
    private(set) var hasLoaded = false
    private(set) var failure: Failure?
    private(set) var isSaving = false
    var editor: DiaryEditor?
    /// Evento pendiente de confirmar su borrado (abre el diálogo).
    var pendingDeletion: DiaryEvent?
    /// Borrado ya confirmado en el diálogo; se aplica cuando el diálogo terminó de cerrarse (T-32).
    private(set) var confirmedDeletion: DiaryEvent?

    var isConfirmingDeletion: Bool {
        get { pendingDeletion != nil }
        set { if !newValue { pendingDeletion = nil } }
    }

    /// `true` cuando hay un borrado confirmado y el diálogo ya no está presentado: la vista lo aplica entonces,
    /// para no cambiar la lista mientras el diálogo se cierra.
    var hasDeletionReadyToCommit: Bool { confirmedDeletion != nil && pendingDeletion == nil }

    /// Aviso compartido de cambios del diario (Hoy, la pestaña Diario y los registros rápidos).
    let changes: DiaryChangeFeed

    @ObservationIgnored private let store: any DiaryStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let newID: @Sendable () -> String
    @ObservationIgnored private let calendar: Calendar

    init(
        store: any DiaryStore,
        changes: DiaryChangeFeed = DiaryChangeFeed(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.changes = changes
        self.calendar = calendar
        self.now = now
        self.newID = newID
    }

    var isEmpty: Bool { hasLoaded && days.isEmpty }

    // MARK: Carga

    func load() async {
        let end = now().addingTimeInterval(86_400)
        let range = UTCInstant(now().addingTimeInterval(-Self.lookback))...UTCInstant(end)
        do {
            let events = try await store.events(in: range)
            // Una sola asignación, y solo si cambió: la lista recibe un único diff coherente.
            let newDays = Self.group(events, calendar: calendar)
            if newDays != days { days = newDays }
            if failure != nil { failure = nil }
        } catch {
            failure = .loadFailed
        }
        hasLoaded = true
    }

    /// Recarga cada vez que otra pantalla cambia el diario, hasta que se cancela la tarea.
    func observeChanges() async {
        let me = ObjectIdentifier(self)
        for await change in changes.changes() where change.origin != me {
            await load()
        }
    }

    /// Agrupa por día local, días y eventos del más reciente al más antiguo (empates por `eventID`).
    /// Secciones identificadas por día de calendario y filas por `eventID`: identidades estables entre cargas.
    static func group(_ events: [DiaryEvent], calendar: Calendar) -> [DiaryDay] {
        let byDay = Dictionary(grouping: events.filter { !$0.deleted }) { calendar.startOfDay(for: $0.at.date) }
        return byDay.keys.sorted(by: >).map { day in
            DiaryDay(
                id: DiaryDay.key(for: day, calendar: calendar),
                start: day,
                events: (byDay[day] ?? []).sorted { ($0.at, $0.eventID) > ($1.at, $1.eventID) })
        }
    }

    // MARK: Editor

    func beginAdd() {
        editor = DiaryEditor(editing: nil, draft: DiaryDraft(now: now()))
    }

    func beginEdit(_ event: DiaryEvent) {
        guard canModify(event) else { return }
        editor = DiaryEditor(editing: event, draft: DiaryDraft(event: event))
    }

    func dismissEditor() {
        editor = nil
    }

    /// Los eventos sintéticos (`PreviewData`) se rotulan y no se editan ni se borran.
    func canModify(_ event: DiaryEvent) -> Bool { !event.synthetic }

    // MARK: Guardar

    /// Alta (`editing == nil`) o edición. Devuelve `true` si se guardó.
    @discardableResult
    func save(_ draft: DiaryDraft, editing: DiaryEvent?) async -> Bool {
        guard draft.isValid, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let instant = UTCInstant(now())
        let event: DiaryEvent
        if let previous = editing {
            event = DiaryEvent(
                eventID: previous.eventID, kind: draft.kind, at: UTCInstant(draft.at), tz: calendar.timeZone.identifier,
                durationMin: draft.durationMin, carbsG: draft.carbsG, text: draft.trimmedText,
                createdAt: previous.createdAt, updatedAt: instant, revision: previous.revision + 1,
                editID: newID(), parentEditID: previous.editID, editedByAppID: Self.appID,
                deleted: false, synthetic: false)
        } else {
            event = DiaryEvent(
                eventID: newID(), kind: draft.kind, at: UTCInstant(draft.at), tz: calendar.timeZone.identifier,
                durationMin: draft.durationMin, carbsG: draft.carbsG, text: draft.trimmedText,
                createdAt: instant, updatedAt: instant, revision: 1,
                editID: newID(), parentEditID: nil, editedByAppID: Self.appID,
                deleted: false, synthetic: false)
        }
        do {
            try await store.save(event)
        } catch {
            failure = .saveFailed
            return false
        }
        editor = nil
        await load()
        changes.notify(from: self)
        return true
    }

    /// El análisis de comidas guardó el evento por su cuenta: cierra el editor, recarga y avisa a las demás pantallas.
    func reloadAfterExternalSave() async {
        editor = nil
        await load()
        changes.notify(from: self)
    }

    // MARK: Borrar

    /// Botón "Borrar" del diálogo: solo anota el borrado. Se aplica con `commitConfirmedDeletion()` cuando el
    /// diálogo ya se cerró (`hasDeletionReadyToCommit`), para no cambiar la lista durante la animación de cierre.
    func confirmDeletion(_ event: DiaryEvent) {
        confirmedDeletion = event
    }

    /// Aplica el borrado confirmado, si lo hay.
    func commitConfirmedDeletion() async {
        guard pendingDeletion == nil, let event = confirmedDeletion else { return }
        confirmedDeletion = nil
        await delete(event)
    }

    /// Tombstone: misma identidad de evento, `deleted = true`, `edit_id` nuevo con la edición anterior como padre.
    func delete(_ event: DiaryEvent) async {
        guard canModify(event), !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        var tombstone = event
        tombstone.deleted = true
        tombstone.updatedAt = UTCInstant(now())
        tombstone.revision = event.revision + 1
        tombstone.parentEditID = event.editID
        tombstone.editID = newID()
        tombstone.editedByAppID = Self.appID
        tombstone.importedFrom = nil
        do {
            try await store.save(tombstone)
        } catch {
            failure = .saveFailed
            return
        }
        pendingDeletion = nil
        await load()
        changes.notify(from: self)
    }
}
