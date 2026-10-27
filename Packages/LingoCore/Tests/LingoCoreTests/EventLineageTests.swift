import Testing
@testable import LingoCore

struct EventLineageTests {
    private let eventID = TestSupport.newID()

    private func version(_ edit: String, parent: String?, text: String?, deleted: Bool = false,
                         archive: String? = nil) -> DiaryEvent {
        DiaryEvent(eventID: eventID, kind: .meal, at: UTCInstant(epochSeconds: 1_793_110_000), tz: TestSupport.tz,
                   carbsG: deleted ? nil : 40, text: deleted ? nil : text,
                   createdAt: UTCInstant(epochSeconds: 1_793_110_000), updatedAt: UTCInstant(epochSeconds: 1_793_110_100),
                   editID: edit, parentEditID: parent, editedByAppID: TestSupport.appID, deleted: deleted,
                   synthetic: false,
                   importedFrom: archive.map { ImportedFrom(appID: "com.otalvaro.lingoscan.astra", archiveID: $0) })
    }

    @Test func descendantWinsAndOlderCopyDoesNotResurrect() async throws {
        let store = try TestSupport.makeStore()
        let a = TestSupport.newID(), b = TestSupport.newID(), c = TestSupport.newID()
        let vA = version(a, parent: nil, text: "Arroz")
        let vB = version(b, parent: a, text: "Arroz con pollo")
        let vC = version(c, parent: b, text: "Arroz con pollo y ensalada")
        #expect(try await store.upsertEvent(vA) == .inserted)
        #expect(try await store.upsertEvent(vA) == .unchanged)
        #expect(try await store.upsertEvent(vB) == .tookDescendant)
        #expect(try await store.upsertEvent(vC) == .tookDescendant)
        // Importar una copia antigua (A, a dos saltos) no vuelve atrás: necesita la tabla de linaje.
        #expect(try await store.upsertEvent(vA) == .keptNewerLocal)
        #expect(try await store.event(id: eventID)?.editID == c)
        #expect(try await store.editAncestors(of: vC) == [EditLink(editID: b, parentEditID: a), EditLink(editID: a, parentEditID: nil)])
        #expect(try await store.editAncestors(of: vA) == [])
        #expect(try await store.conflicts().isEmpty)
    }

    @Test func divergentBranchesKeepLocalAndRecordConflict() async throws {
        let store = try TestSupport.makeStore()
        let a = TestSupport.newID(), local = TestSupport.newID(), remote = TestSupport.newID(), archive = TestSupport.newID()
        try await store.upsertEvent(version(a, parent: nil, text: "Base"))
        try await store.upsertEvent(version(local, parent: a, text: "Edición local"))
        let remoteVersion = version(remote, parent: a, text: "Edición remota", archive: archive)
        #expect(try await store.upsertEvent(remoteVersion) == .divergent)
        #expect(try await store.upsertEvent(remoteVersion) == .divergent)
        #expect(try await store.event(id: eventID)?.text == "Edición local")
        let conflicts = try await store.conflicts(id: eventID)
        #expect(conflicts.count == 1)
        let conflict = try #require(conflicts.first)
        #expect(conflict.resolution == .divergent && conflict.kind == .event && conflict.remoteArchiveID == archive)
        #expect(try #require(conflict.remote).decoded(as: DiaryEvent.self) == remoteVersion)

        // La elección del usuario es una edición nueva cuyo padre es la versión elegida (aquí la remota).
        let choice = version(TestSupport.newID(), parent: remote, text: "Edición remota")
        #expect(try await store.resolveEventConflict(choice: choice))
        #expect(try await store.event(id: eventID)?.editID == choice.editID)
        // La versión local descartada es otra rama: reimportarla no gana.
        #expect(try await store.upsertEvent(version(local, parent: a, text: "Edición local")) == .divergent)
        // Una elección cuyo padre no es ninguna versión en conflicto se rechaza.
        #expect(try await store.resolveEventConflict(choice: version(TestSupport.newID(), parent: TestSupport.newID(), text: "x")) == false)
    }

    @Test func missingLinkIsLineageUnknownNotDivergent() async throws {
        let store = try TestSupport.makeStore()
        let a = TestSupport.newID()
        try await store.upsertEvent(version(a, parent: nil, text: "Base"))
        let orphan = version(TestSupport.newID(), parent: TestSupport.newID(), text: "Padre desconocido")
        #expect(try await store.upsertEvent(orphan) == .lineageUnknown)
        #expect(try await store.conflicts(id: eventID).map(\.resolution) == [.lineageUnknown])
        #expect(try await store.event(id: eventID)?.editID == a)
        #expect(try await store.editAncestors(of: orphan) == nil)
    }

    @Test func ancestorsFromPackageResolveTwoHopDescendant() async throws {
        let store = try TestSupport.makeStore()
        let a = TestSupport.newID(), b = TestSupport.newID(), c = TestSupport.newID()
        try await store.upsertEvent(version(a, parent: nil, text: "Base"))
        // C llega sin haber visto B; `edit_ancestors` del paquete aporta el eslabón.
        let vC = version(c, parent: b, text: "Dos saltos")
        let outcome = try await store.upsertEvent(vC, ancestors: [EditLink(editID: b, parentEditID: a), EditLink(editID: a, parentEditID: nil)])
        #expect(outcome == .tookDescendant)
    }

    @Test func tombstoneVersusEdit() async throws {
        let store = try TestSupport.makeStore()
        let a = TestSupport.newID(), b = TestSupport.newID(), t = TestSupport.newID()
        try await store.upsertEvent(version(a, parent: nil, text: "Base"))
        try await store.upsertEvent(version(b, parent: a, text: "Editada"))
        let tombstone = version(t, parent: b, text: nil, deleted: true)
        #expect(try await store.upsertEvent(tombstone) == .tookDescendant)
        #expect(try await store.upsertEvent(version(b, parent: a, text: "Editada")) == .keptNewerLocal)
        let stored = try #require(try await store.event(id: eventID))
        #expect(stored.deleted && stored.text == nil && stored.carbsG == nil)
        // Una edición divergente del tombstone no lo aplica en silencio ni lo deshace.
        #expect(try await store.upsertEvent(version(TestSupport.newID(), parent: a, text: "Otra rama")) == .divergent)
        #expect(try await store.event(id: eventID)?.deleted == true)
    }
}
