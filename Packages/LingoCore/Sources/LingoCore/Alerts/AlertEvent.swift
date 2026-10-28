/// Una alerta que el evaluador decidió notificar. Sin textos: la app los compone (`AlertMessageComposer`)
/// a partir de `messageKey` y de los valores.
public struct AlertEvent: Sendable, Hashable, Codable {
    public let kind: AlertKind
    /// Instante de la evaluación que la disparó.
    public let at: UTCInstant
    /// Última lectura elegible en mg/dL; `nil` en "sin datos".
    public let value: Int?
    /// Pendiente de la ventana en mg/dL por minuto, si se pudo calcular.
    public let slopePerMinute: Double?
    /// Desde cuándo se cumple la condición (primera lectura fuera de rango, inicio de la ventana de la pendiente
    /// o última lectura elegible en "sin datos").
    public let since: UTCInstant?
    /// Clave estable del mensaje (`alert.high`, `alert.low`, …).
    public let messageKey: String

    public init(kind: AlertKind, at: UTCInstant, value: Int?, slopePerMinute: Double?, since: UTCInstant?, messageKey: String? = nil) {
        self.kind = kind
        self.at = at
        self.value = value
        self.slopePerMinute = slopePerMinute
        self.since = since
        self.messageKey = messageKey ?? "alert.\(kind.rawValue)"
    }
}
