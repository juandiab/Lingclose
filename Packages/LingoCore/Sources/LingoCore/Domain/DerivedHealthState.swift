/// Estado derivado de un sujeto para una escritora (contrato §5.4, C4).
public enum DerivedHealthState: String, Sendable, Hashable, CaseIterable {
    /// Hay al menos un intento `written` con el `sync_version` más alto conocido.
    case written
    /// El último intento es `unknown` y no hay `written` para esa versión: reconciliar consultando Health.
    case unknown
    /// El último intento es `failed` y no hay `written`.
    case failed
    /// No hay intentos.
    case none
}
