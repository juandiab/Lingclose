import SwiftUI

/// Miniatura estática de cada fondo (Canvas: barata, sin GPU propia).
struct BackgroundThumbnail: View {
    let style: BackgroundStyle

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Tokens.Studio.background))
            if style == .hexVault { drawVault(&context, size) }
        }
        .overlay {
            if style == .none {
                Image(systemName: "circle.slash")
                    .font(.title3)
                    .foregroundStyle(Tokens.Studio.textTertiary)
            }
        }
        .accessibilityHidden(true)
    }

    /// Rejilla hexagonal con un foco del color "en rango".
    private func drawVault(_ context: inout GraphicsContext, _ size: CGSize) {
        let radius: CGFloat = 9
        let width = radius * sqrt(3)
        let glow = CGPoint(x: size.width * 0.62, y: size.height * 0.45)
        let tint = BackgroundPalette.Emission.inRange
        var row = 0
        var y: CGFloat = -radius
        while y < size.height + radius {
            var x: CGFloat = row.isMultiple(of: 2) ? 0 : width / 2
            while x < size.width + width {
                var hex = Path()
                for index in 0..<6 {
                    let angle = CGFloat(index) * .pi / 3 + .pi / 6
                    let point = CGPoint(x: x + radius * cos(angle), y: y + radius * sin(angle))
                    if index == 0 { hex.move(to: point) } else { hex.addLine(to: point) }
                }
                hex.closeSubpath()
                let lit = max(0, 1 - hypot(x - glow.x, y - glow.y) / 28)
                let color = Color(
                    red: Double(tint.x) * (0.45 + 0.55 * lit),
                    green: Double(tint.y) * (0.45 + 0.55 * lit),
                    blue: Double(tint.z) * (0.45 + 0.55 * lit))
                context.stroke(hex, with: .color(color.opacity(0.18 + 0.7 * lit)), lineWidth: 0.6 + lit)
                x += width
            }
            y += radius * 1.5
            row += 1
        }
    }
}

#Preview {
    HStack {
        BackgroundThumbnail(style: .hexVault)
        BackgroundThumbnail(style: .none)
    }
    .frame(height: 72)
    .padding()
}
