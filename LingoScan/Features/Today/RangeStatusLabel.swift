import SwiftUI

/// Estado del último valor respecto al rango de referencia (no médico) o del dato atrasado.
/// Siempre icono y texto: el color nunca es la única señal.
struct RangeStatusLabel: View {
    let value: Int
    let isStale: Bool
    var low = ReferenceLines.defaultLow
    var high = ReferenceLines.defaultHigh

    var body: some View {
        if isStale {
            Label(
                String(localized: "today.status.stale", defaultValue: "Dato atrasado"),
                systemImage: "clock.badge.exclamationmark"
            )
            .foregroundStyle(Tokens.Palette.stale)
        } else if value < low {
            Label(
                String(localized: "today.status.below", defaultValue: "Por debajo del rango de referencia"),
                systemImage: "arrow.down.circle"
            )
            .foregroundStyle(Tokens.Palette.outOfRange)
        } else if value > high {
            Label(
                String(localized: "today.status.above", defaultValue: "Por encima del rango de referencia"),
                systemImage: "arrow.up.circle"
            )
            .foregroundStyle(Tokens.Palette.outOfRange)
        } else {
            Label(
                String(localized: "today.status.inRange", defaultValue: "En el rango de referencia"),
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(Tokens.Palette.inRange)
        }
    }
}
