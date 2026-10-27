import SwiftUI

/// La búsqueda solo existe mientras hay catálogo que filtrar.
struct CatalogSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $text,
                prompt: Text(String(localized: "llm.search", defaultValue: "Buscar por nombre o id")))
        } else {
            content
        }
    }
}
