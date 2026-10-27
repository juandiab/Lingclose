import SwiftUI

/// Un modelo del catálogo: nombre, imágenes, precio con fuente y recomendación con su motivo.
struct ModelRow: View {
    let model: LLMModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.displayName)
                    .font(.headline)
                Spacer(minLength: Tokens.Spacing.xs)
                recommendationChip
            }
            Text(model.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(model.imageSupportText)
                .font(.subheadline)
            Text(model.priceText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var reason: String? {
        switch model.recommendation {
        case .recommended(let reason), .notRecommended(let reason): reason
        case .unknown: nil
        }
    }

    @ViewBuilder
    private var recommendationChip: some View {
        switch model.recommendation {
        case .recommended:
            chip(String(localized: "llm.recommended", defaultValue: "Recomendado"), color: Tokens.Palette.inRange)
        case .notRecommended:
            chip(String(localized: "llm.notRecommended", defaultValue: "No recomendado"), color: Tokens.Palette.gap)
        case .unknown:
            EmptyView()
        }
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Tokens.Spacing.xs)
            .padding(.vertical, Tokens.Spacing.xxs)
            .background(color.opacity(0.2), in: .capsule)
    }
}
