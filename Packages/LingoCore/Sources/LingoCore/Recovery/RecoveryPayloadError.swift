/// Error de decodificación o de esquema de la carga útil. Nunca incluye valores, solo la ruta.
public enum RecoveryPayloadError: Error, Sendable, Equatable, CustomStringConvertible {
    /// JSON mal formado, clave obligatoria ausente o `null` donde no se admite.
    case malformed(String)
    /// La clave existe pero su valor no cumple `schemas/recovery_payload.schema.json`.
    case invalid(path: String, reason: String)
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .malformed(let what): "carga útil mal formada: \(what)"
        case .invalid(let path, let reason): "carga útil inválida en \(path): \(reason)"
        case .unsupportedVersion(let v): "payload_version \(v) no soportada"
        }
    }
}
