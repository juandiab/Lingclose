/// Paquete ajeno ya importado: su `archive_id` hace que reimportarlo sea un no-op (contrato §8.1).
public struct ImportedArchiveRecord: Sendable, Hashable {
    public var archiveID: String
    public var producerAppID: String
    public var createdAt: UTCInstant
    public var importedAt: UTCInstant
    public var sessions: Int
    public var readings: Int
    public var events: Int
    public var ledgerEntries: Int
    public var conflicts: Int

    public init(archiveID: String, producerAppID: String, createdAt: UTCInstant, importedAt: UTCInstant,
                sessions: Int, readings: Int, events: Int, ledgerEntries: Int, conflicts: Int) {
        self.archiveID = archiveID
        self.producerAppID = producerAppID
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.sessions = sessions
        self.readings = readings
        self.events = events
        self.ledgerEntries = ledgerEntries
        self.conflicts = conflicts
    }
}
