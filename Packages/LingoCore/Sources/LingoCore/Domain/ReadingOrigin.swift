/// Ruta por la que llegó una lectura (`origin`, contrato §5.2).
public enum ReadingOrigin: String, Sendable, Codable, Hashable, CaseIterable {
    case live
    case embeddedHistory = "embedded_history"
    case backfillHistory = "backfill_history"
    case backfillFast = "backfill_fast"
    case `import`

    /// Precedencia del contrato §5.2: `live > backfill_fast > backfill_history > embedded_history > import`.
    public var precedence: Int {
        switch self {
        case .live: 5
        case .backfillFast: 4
        case .backfillHistory: 3
        case .embeddedHistory: 2
        case .import: 1
        }
    }
}
