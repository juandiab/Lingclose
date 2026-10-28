/// Memoria del evaluador entre llamadas (se persiste como JSON).
/// - `lastFired`: último aviso por tipo, para el silencio entre avisos.
/// - `activeSince`: tipos cuya condición se cumple ahora y desde cuándo. Mientras un tipo sigue activo solo se
///   repite tras el silencio entre avisos; al volver al rango y salir de nuevo se avisa de inmediato.
public struct AlertState: Sendable, Hashable, Codable {
    public var lastFired: [AlertKind: UTCInstant]
    public var activeSince: [AlertKind: UTCInstant]

    public init(lastFired: [AlertKind: UTCInstant] = [:], activeSince: [AlertKind: UTCInstant] = [:]) {
        self.lastFired = lastFired
        self.activeSince = activeSince
    }

    public func isActive(_ kind: AlertKind) -> Bool { activeSince[kind] != nil }

    /// Registra un aviso entregado fuera del evaluador (p. ej. la notificación "sin datos" programada que iOS
    /// mostró con la app suspendida), para que no se repita antes del silencio entre avisos.
    public func assumingDelivered(_ kind: AlertKind, at instant: UTCInstant, since: UTCInstant? = nil) -> AlertState {
        var copy = self
        if (copy.lastFired[kind].map { $0 < instant }) ?? true { copy.lastFired[kind] = instant }
        if copy.activeSince[kind] == nil { copy.activeSince[kind] = since ?? instant }
        return copy
    }

    private enum CodingKeys: String, CodingKey { case lastFired, activeSince }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastFired = try c.decodeIfPresent([AlertKind: UTCInstant].self, forKey: .lastFired) ?? [:]
        activeSince = try c.decodeIfPresent([AlertKind: UTCInstant].self, forKey: .activeSince) ?? [:]
    }
}
