import Foundation

/// Contexto **opcional** que acompaña al snapshot cuando el usuario lo permite (T-33): comidas con nombre y macros,
/// sueño por noche, pasos por día y perfil general. Va en un bloque aparte del mensaje, después del JSON del
/// snapshot, que no cambia (ni su `format_version` ni Compartir). Claves snake_case y JSON ordenado (misma
/// configuración que el snapshot): mismo contexto, mismos bytes. Sin ids, fotos, notas ni supuestos del asistente.
struct ReportAnalysisContext: Sendable, Hashable, Codable {
    /// Solo comidas presentes en el snapshot compactado, unidas por `at`.
    var meals: [ReportAnalysisMealContext]?
    /// Una por noche con datos, con la convención de `NightReport`.
    var sleep: [SleepNight]?
    var activity: ReportAnalysisActivityContext?
    var profile: ReportAnalysisProfileContext?

    var isEmpty: Bool { meals == nil && sleep == nil && activity == nil && profile == nil }

    /// Bloques que van, con nombres legibles para la cabecera del mensaje (en español, como el resto del prompt).
    var includedBlocks: [String] {
        var blocks: [String] = []
        if meals != nil { blocks.append("comidas con nombre") }
        if sleep != nil { blocks.append("sueño") }
        if activity != nil { blocks.append("pasos") }
        if profile != nil { blocks.append("perfil") }
        return blocks
    }

    /// JSON con claves ordenadas y sin escapar `/`.
    func jsonData() throws -> Data { try Self.encoder.encode(self) }

    var jsonByteCount: Int { (try? jsonData())?.count ?? Int.max }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Bloques encendidos que no tienen nada que enviar (Salud sin datos o sin permiso, comidas sin nombre): la hoja
    /// lo dice en una línea.
    static func gaps(in context: ReportAnalysisContext?, sharing: ReportAnalysisSharing) -> [ReportAnalysisContextGap] {
        var gaps: [ReportAnalysisContextGap] = []
        if sharing.meals, context?.meals == nil { gaps.append(.meals) }
        if sharing.sleepActivity, context?.sleep == nil { gaps.append(.sleep) }
        if sharing.sleepActivity, context?.activity == nil { gaps.append(.steps) }
        if sharing.profile, context?.profile == nil { gaps.append(.profile) }
        return gaps
    }
}
