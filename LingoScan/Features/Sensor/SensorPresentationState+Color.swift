import SwiftUI

extension SensorPresentationState {
    /// Color del icono según el tono. Siempre acompaña a un texto y a un icono distinto.
    var tint: Color {
        switch tone {
        case .good: Tokens.Palette.inRange
        case .attention: Tokens.Palette.stale
        case .error: Tokens.Palette.error
        case .neutral: .secondary
        }
    }
}
