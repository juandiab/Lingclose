import SwiftUI

/// Número grande con unidad: `.rounded`, dígitos de ancho fijo y transición numérica.
struct MetricText: View {
    enum Size {
        case hero
        case large
        /// Lectura del cursor y métricas compactas.
        case medium
        case regular

        var valueFont: Font {
            switch self {
            case .hero: .system(.largeTitle, design: .rounded, weight: .bold).scaled(by: 2.2)
            case .large: .system(.title, design: .rounded, weight: .semibold)
            case .medium: .system(.title3, design: .rounded, weight: .semibold)
            case .regular: .system(.body, design: .rounded, weight: .medium)
            }
        }

        var unitFont: Font {
            switch self {
            case .hero: .title3
            case .large: .subheadline
            case .medium: .caption
            case .regular: .footnote
            }
        }
    }

    /// Valor entero; `nil` se muestra como "--".
    let value: Int?
    var unit: String?
    var size: Size = .hero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xxs) {
            valueText
                .font(size.valueFont)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value ?? 0)))
                .animation(reduceMotion ? nil : .smooth, value: value)
            if let unit {
                Text(unit)
                    .font(size.unitFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var valueText: Text {
        if let value {
            Text(value, format: .number.grouping(.never))
        } else {
            Text(verbatim: "--")
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        MetricText(value: 142, unit: "mg/dL")
        MetricText(value: 98, unit: "mg/dL", size: .large)
        MetricText(value: nil, size: .regular)
    }
    .padding()
}
