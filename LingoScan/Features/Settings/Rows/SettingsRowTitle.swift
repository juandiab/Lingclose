import SwiftUI

/// Título de fila de Ajustes con icono SF y, si hace falta, una línea de explicación debajo (p. ej. por qué una opción
/// está fija o no disponible). Un solo patrón para todas las filas de la pantalla principal.
struct SettingsRowTitle: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        Label {
            // Un solo `Text`: con texto grande el título y la explicación se parten juntos, sin sangrías raras.
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
    }

    /// Título y, en otra línea, la explicación en pie de página y color secundario. `AttributedString` evita una
    /// clave de formato nueva en el catálogo.
    private var text: AttributedString {
        var result = AttributedString(title)
        guard let detail else { return result }
        // Separador de línea (U+2028), no de párrafo: con tamaños de accesibilidad la fila sangra cada párrafo nuevo.
        var line = AttributedString("\u{2028}" + detail)
        line.font = .footnote
        line.foregroundColor = .secondary
        result.append(line)
        return result
    }
}
