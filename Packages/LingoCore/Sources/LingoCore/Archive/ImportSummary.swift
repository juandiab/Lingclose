import Foundation

/// Resumen de una importación (contrato §8.6): nuevas, actualizadas, idénticas, conflictos, rechazadas.
public struct ImportSummary: Sendable, Hashable {
    /// Resultado por entidad. Cada registro del paquete cae en exactamente una categoría.
    public struct Counts: Sendable, Hashable {
        /// No existía en la base: se importó.
        public var new = 0
        /// Existía y cambió (se tomó la versión remota, subió el `origin`, cambió una sesión…).
        public var updated = 0
        /// Existía y no cambió, sin conflicto.
        public var identical = 0
        /// Se conservó lo local y la diferencia quedó en `conflicts`.
        public var conflicted = 0

        public init(new: Int = 0, updated: Int = 0, identical: Int = 0, conflicted: Int = 0) {
            self.new = new
            self.updated = updated
            self.identical = identical
            self.conflicted = conflicted
        }

        public var total: Int { new + updated + identical + conflicted }
    }

    public var archiveID: String
    public var producerAppID: String
    public var createdAt: UTCInstant
    /// `true` si el `archive_id` ya estaba importado o era propio: no se hizo nada (§8.1).
    public var alreadyKnown: Bool
    public var sessions = Counts()
    public var readings = Counts()
    public var events = Counts()
    public var ledger = Counts()
    /// Filas añadidas a `conflicts` (los conflictos idénticos ya registrados no cuentan).
    public var conflictsRecorded = 0
    /// Registros que no entraron: lecturas y sujetos de ledger de una sesión sintética equivalente a una real (o al revés).
    public var rejected = 0
    /// `manifest.health.handover_at_utc` del paquete (§7.4).
    public var handoverAt: UTCInstant?
    public var warnings: [String] = []

    public init(archiveID: String, producerAppID: String, createdAt: UTCInstant, alreadyKnown: Bool,
                handoverAt: UTCInstant? = nil) {
        self.archiveID = archiveID
        self.producerAppID = producerAppID
        self.createdAt = createdAt
        self.alreadyKnown = alreadyKnown
        self.handoverAt = handoverAt
    }

    public var newTotal: Int { sessions.new + readings.new + events.new + ledger.new }
    public var updatedTotal: Int { sessions.updated + readings.updated + events.updated }
    public var identicalTotal: Int { sessions.identical + readings.identical + events.identical + ledger.identical }
}

/// Resultado de un paquete dentro de `ArchiveImporter.importAll`.
public enum PackageImportOutcome: Sendable {
    case imported(ImportSummary)
    /// El paquete es propio o ya se importó; no cambió nada.
    case skipped(ImportSummary)
    /// Rechazado por la validación (o por un fallo de la base): la base quedó como estaba.
    case rejected(name: String, reason: String, code: String)

    public var name: String? {
        if case .rejected(let n, _, _) = self { return n }
        return nil
    }
}
