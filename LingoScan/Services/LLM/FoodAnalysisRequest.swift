import Foundation

/// Lo único que sale del teléfono para analizar una comida: la foto (JPEG ya reducido) y la
/// descripción del usuario. Nunca glucosa, Salud ni entrenamientos. `locale` solo elige el idioma
/// de `name` y `assumptions` en la respuesta.
struct FoodAnalysisRequest: Sendable {
    var imageJPEG: Data?
    var description: String?
    var locale: String

    init(imageJPEG: Data? = nil, description: String? = nil, locale: String = "es-CO") {
        self.imageJPEG = imageJPEG
        self.description = description
        self.locale = locale
    }

    /// Descripción sin espacios sobrantes; `nil` si está vacía.
    var trimmedDescription: String? {
        let t = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    var hasImage: Bool { !(imageJPEG?.isEmpty ?? true) }
}
