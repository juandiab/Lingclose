import SwiftUI

/// Ajustes › Personalización › Apariencia: Sistema, Claro u Oscuro. Segmentado con texto normal; con tamaños de
/// accesibilidad pasa a menú, porque el segmentado no crece con Dynamic Type y se vuelve ilegible.
struct AppearanceRow: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                title
                picker
                    .pickerStyle(.segmented)
                    .labelsHidden()
            }
            .padding(.vertical, Tokens.Spacing.xxs)
        }
    }

    private var picker: some View {
        Picker(selection: $appearance) {
            ForEach(AppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            title
        }
    }

    private var title: some View {
        Label(String(localized: "settings.appearance", defaultValue: "Apariencia"), systemImage: "circle.lefthalf.filled")
    }
}

#Preview {
    Form {
        AppearanceRow()
    }
}
