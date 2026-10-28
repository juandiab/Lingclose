/// Familia de un consejo: qué tipo de acción propone. La app la usa para elegir el icono.
public enum CoachingCategory: String, Sendable, Hashable, Codable, CaseIterable {
    /// Moverse (caminar, movimiento suave).
    case move
    /// Beber agua.
    case hydrate
    /// Comer algo o evitar comer más.
    case food
    /// Descanso, estrés, sueño.
    case rest
    /// Esperar a la siguiente lectura.
    case wait
    /// Comprobar algo (síntomas, sensor, teléfono, Bluetooth).
    case check
}
