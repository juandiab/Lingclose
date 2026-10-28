/// Lectura solo-lectura del perfil de Salud. La app usa `HealthKitProfileReader`; las pruebas y la
/// previsualización inyectan un doble. `readProfile` pide permiso de lectura para los cuatro tipos la primera
/// vez y devuelve lo que haya; lanza solo si Salud no está disponible o la petición de permiso falla.
protocol HealthProfileReading: Sendable {
    func readProfile() async throws -> HealthProfile
}

enum HealthProfileError: Error, Sendable, Equatable {
    case unavailable
    case authorizationFailed(String)
}
