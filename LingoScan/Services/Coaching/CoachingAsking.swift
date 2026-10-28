/// Quien responde a "Preguntar al asistente" (T-25). La app usa `CoachingAssistantService`; la previsualización,
/// `PreviewCoachingAssistant`. Nunca se llama solo: una petición por toque, sin reintentos.
protocol CoachingAsking: Sendable {
    /// Hay proveedor, clave y modelo del asistente de comidas. Sin eso el botón no aparece.
    func isConfigured() async -> Bool
    func ask(_ record: CoachingRecord) async throws -> CoachingAnswer
}
