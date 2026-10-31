import LingoCore

/// Una comida del snapshot con su nombre y nutrientes (T-33). `at` es el mismo instante que en el snapshot para que
/// la IA las cruce. Lo desconocido no se envía (clave ausente), nunca como 0.
struct ReportAnalysisMealContext: Sendable, Hashable, Codable {
    var at: UTCInstant
    /// Nombre del registro de nutrición o, sin registro, el texto del evento; máx. 60 caracteres, una línea.
    var name: String?
    var kcal: Double?
    var carbsG: Double?
    var proteinG: Double?
    var fatG: Double?
    /// `assistant` (reconocida por el asistente), `label` (etiqueta nutricional) o `manual`; ausente sin registro.
    var source: String?
    /// `food` (plato reconocido) o `nutrition_label` (etiqueta); ausente sin registro.
    var kind: String?

    enum CodingKeys: String, CodingKey {
        case at, name, kcal
        case carbsG = "carbs_g"
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case source, kind
    }
}
