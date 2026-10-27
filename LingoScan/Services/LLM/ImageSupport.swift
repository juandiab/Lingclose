/// Si un modelo acepta imágenes. Solo `.confirmed` permite enviar la foto; `.unconfirmed` se muestra
/// como "No confirmado" y se trata como "no" a la hora de analizar.
enum ImageSupport: Sendable, Hashable, Codable {
    case confirmed
    case none
    case unconfirmed
}
