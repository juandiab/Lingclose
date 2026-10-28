/// Un consejo de bienestar para después de una alerta (T-25). Sin UI ni catálogo de cadenas: `id` es la base de
/// las claves localizables (`coaching.<id>.title`, `coaching.<id>.body`) y `title`/`body` son el texto por defecto en
/// español, que la app usa si la clave no está traducida. Nunca habla de insulina, fármacos ni dosis.
public struct CoachingTip: Sendable, Hashable, Codable, Identifiable {
    /// Identificador estable (`walkAfterMeal`, `lowSymptoms`, …).
    public let id: String
    /// Título corto, texto por defecto en español.
    public let title: String
    /// Una frase de como mucho `CoachingTip.maxBodyLength` caracteres, texto por defecto en español.
    public let body: String
    public let category: CoachingCategory

    public static let maxBodyLength = 120

    public init(id: String, title: String, body: String, category: CoachingCategory) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
    }

    /// Clave localizable del título.
    public var titleKey: String { "coaching.\(id).title" }
    /// Clave localizable del cuerpo.
    public var bodyKey: String { "coaching.\(id).body" }
}
