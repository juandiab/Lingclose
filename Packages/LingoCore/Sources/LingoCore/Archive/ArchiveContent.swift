import Foundation

/// Una versión de un evento con su cadena de ancestros (`edit_ancestors`, contrato §5.3, draft.4).
/// `ancestors == nil` significa "el paquete no la traía o no se puede demostrar"; `[]` es una creación.
public struct ArchiveEvent: Sendable, Hashable {
    public var event: DiaryEvent
    public var ancestors: [EditLink]?

    public init(event: DiaryEvent, ancestors: [EditLink]?) {
        self.event = event
        self.ancestors = ancestors
    }
}

/// Contenido de un paquete (o el estado completo de la base, para exportar).
public struct ArchiveContent: Sendable {
    public var sessions: [SensorSessionRecord]
    public var readings: [GlucoseReading]
    public var events: [ArchiveEvent]
    public var ledger: [HealthLedgerEntry]
    public var conflicts: [ConflictRecord]

    public init(sessions: [SensorSessionRecord] = [], readings: [GlucoseReading] = [], events: [ArchiveEvent] = [],
                ledger: [HealthLedgerEntry] = [], conflicts: [ConflictRecord] = []) {
        self.sessions = sessions
        self.readings = readings
        self.events = events
        self.ledger = ledger
        self.conflicts = conflicts
    }
}

/// Paquete leído y validado por completo: es el área de staging en memoria del importador (§8.3).
public struct ArchivePackage: Sendable {
    public let url: URL
    public let manifest: ArchiveManifest
    /// SHA-256 de los bytes de `manifest.json`.
    public let manifestSHA256: String
    public let content: ArchiveContent
    /// Avisos no fatales (archivos presentes y no listados, `measured_at` lejos de la fórmula…).
    public let warnings: [String]
}

/// Resultado de `LingoScanArchiveWriter.write`.
public struct WrittenArchive: Sendable {
    public let url: URL
    public let manifest: ArchiveManifest
    public let manifestSHA256: String
}
