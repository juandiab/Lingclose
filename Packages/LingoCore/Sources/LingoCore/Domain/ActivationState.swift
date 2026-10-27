/// Estado del intento de activación (`RECUPERACION_V1.md` §activation.state). Local de LingoScan:
/// en `sessions.json` viaja como clave adicional `activation_state` (el esquema admite claves extra).
public enum ActivationState: String, Sendable, Codable, Hashable, CaseIterable {
    case prepared
    case sent
    case responseSaved = "response_saved"
    case authenticated
    case failed
}
