/// Lo que la UI puede mostrar de una identidad instalada: etiqueta y familias servidas.
/// Nunca contiene claves, certificado ni JSON.
struct IdentitySummary: Sendable, Hashable, Identifiable {
    let label: String
    /// Nombres de familia (`lingo`, `libre3`) que la identidad sirve.
    let families: [String]

    var id: String { label }
}
