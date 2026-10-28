/// Tipos de alerta de glucosa (T-24). Informativas: LingoScan es bienestar, no un dispositivo médico.
public enum AlertKind: String, Sendable, Hashable, Codable, CaseIterable, CodingKeyRepresentable {
    case high, low, risingFast, fallingFast, noData

    /// Silencio entre avisos del mismo tipo por defecto: 30 min; "sin datos", 60 min.
    public var defaultCooldownMinutes: Int { self == .noData ? 60 : 30 }
}
