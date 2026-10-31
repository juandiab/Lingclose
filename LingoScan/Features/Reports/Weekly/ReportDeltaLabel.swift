import SwiftUI

/// Cambio con flecha y color (verde mejora, ámbar empeora, gris sin valoración); el texto siempre acompaña al color.
struct ReportDeltaLabel: View {
    let delta: ReportDelta

    var body: some View {
        Label(delta.text, systemImage: delta.systemImage)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(delta.color)
            .labelStyle(.titleAndIcon)
    }
}
