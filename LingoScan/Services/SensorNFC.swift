/// Operaciones NFC del coordinador, separadas y sin fallback entre sí.
protocol SensorNFC: Sendable {
    /// Solo `0xA1`. Ningún camino llega a `0xA0` ni a `0xA8`.
    func readPatchInfo() async throws -> SensorProfile
    /// Solo `0xA0` sobre un sensor sin activar, con un ticket emitido tras confirmación.
    func activate(ticket: ActivationTicket) async throws -> ActivationResponse
}
