import LingoCore
import SwiftUI

/// Un consejo de reglas: icono de su familia, título y la frase.
struct CoachingTipRow: View {
    let tip: CoachingTip

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(tip.localizedTitle)
                    .font(.subheadline)
                    .bold()
                Text(tip.localizedBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: tip.category.systemImage)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}
