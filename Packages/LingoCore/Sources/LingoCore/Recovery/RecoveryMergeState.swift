/// Estado sobre el que se aplica la fusión: sesiones activas, alias, históricos y conflictos.
public struct RecoveryMergeState: Sendable, Hashable {
    /// Copia activa por `session_id` canónico.
    public var sessions: [String: RecoveryPayload.Session]
    /// `exported_by_app_id` de la copia activa (desempate entre exportadores con la misma `sequence`).
    public var exporters: [String: String]
    /// `session_id` remoto → canónico local, añadido por la regla de equivalencia (±120 s).
    public var aliases: [String: String]
    public var historical: [RecoveryMergeHistoricalAttempt]
    public var conflicts: [RecoveryMergeConflict]

    public init(
        sessions: [String: RecoveryPayload.Session] = [:],
        exporters: [String: String] = [:],
        aliases: [String: String] = [:],
        historical: [RecoveryMergeHistoricalAttempt] = [],
        conflicts: [RecoveryMergeConflict] = []
    ) {
        self.sessions = sessions
        self.exporters = exporters
        self.aliases = aliases
        self.historical = historical
        self.conflicts = conflicts
    }
}
