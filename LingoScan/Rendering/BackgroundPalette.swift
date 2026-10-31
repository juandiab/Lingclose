import simd

/// Paleta del fondo derivada del tono de glucosa. Una entrada por renderer (hoy solo Hex Vault).
///
/// Intensidad baja a propósito: es una app de salud y la curva y los números mandan sobre el fondo.
struct BackgroundPalette: Equatable, Sendable {
    var vault: VaultPalette

    /// Colores sRGB (0–1) emitidos por tono. En rango sale de `Tokens.Palette.inRange` (variante oscura),
    /// alto del ámbar de `outOfRange` (oscuro), bajo de un azul frío; neutro es un gris azulado apagado.
    enum Emission {
        static let inRange = SIMD3<Float>(0.35, 0.72, 0.52)
        static let high = SIMD3<Float>(0.98, 0.69, 0.25)
        static let low = SIMD3<Float>(0.36, 0.56, 1.00)
        static let neutral = SIMD3<Float>(0.46, 0.48, 0.56)
        /// Cuánto se aclara el color para la parte caliente de la estela.
        static let highlight: Float = 0.35
        /// El neutro además se atenúa: sin dato fresco el fondo casi desaparece.
        static let neutralDim: Float = 0.6
    }

    /// Color sRGB emitido para un tono.
    static func emission(for tone: GlucoseBackgroundTone) -> SIMD3<Float> {
        switch tone {
        case .inRange: Emission.inRange
        case .high: Emission.high
        case .low: Emission.low
        case .neutral: Emission.neutral * Emission.neutralDim
        }
    }

    init(vault: VaultPalette) {
        self.vault = vault
    }

    init(tone: GlucoseBackgroundTone) {
        let base = Self.emission(for: tone)
        let light = simd_mix(base, SIMD3(repeating: tone == .neutral ? Emission.neutralDim : 1),
                             SIMD3(repeating: Emission.highlight))
        vault = VaultPalette(colorA: VaultPalette.linear(base), colorB: VaultPalette.linear(light))
    }

    static let idle = BackgroundPalette(tone: .neutral)
}
