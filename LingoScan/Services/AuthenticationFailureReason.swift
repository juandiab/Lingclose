import LingoCore

/// Motivo de `SessionState.authenticationFailed`. Un corte (`interrupted`) nunca
/// se etiqueta como credenciales equivocadas (`docs/FORK_RWDK.md` § T-02).
enum AuthenticationFailureReason: Sendable, Equatable {
    case interrupted(AuthInterruptionEvidence)
    case sensorCertificateInvalid
    case noTrustedKeys
    case other(String)

    /// La app murió entre `sent` y `response_saved` (`RECUPERACION_V1.md` §4.6):
    /// no se reenvía `0xA0` ni `0xA8` automáticamente.
    static func incompleteActivation(_ state: ActivationState) -> AuthenticationFailureReason {
        .other("intento de activación incompleto (estado \(state.rawValue))")
    }

    var isInterruption: Bool {
        if case .interrupted = self { return true }
        return false
    }

    /// Texto corto y sin secretos para `event_log` y para persistir el bloqueo.
    var summary: String {
        switch self {
        case .interrupted(let evidence):
            "interrumpido (último comando \(evidence.lastCommandText), \(evidence.underlying))"
        case .sensorCertificateInvalid:
            "certificado del sensor no verificado"
        case .noTrustedKeys:
            "sin claves de firma de confianza"
        case .other(let text):
            text
        }
    }
}
