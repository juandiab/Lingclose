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

    /// Variante clara de Hex Vault (T-30). Mismos colores de tono que en oscuro, pero como veladura sobre una base
    /// casi blanca: la luz no puede sumarse al blanco, así que tiñe la base hacia el color del tono.
    enum Light {
        /// Base sRGB: gris cálido muy suave (≈ 0,97).
        static let base = SIMD3<Float>(0.972, 0.966, 0.954)
        /// Cuánto oscurecen las líneas de la rejilla la base en reposo (fracción, antes del shimmer).
        static let latticeShade: Float = 0.12
        /// Opacidad máxima de la veladura del tono sobre una arista encendida.
        static let veil: Float = 0.42
    }

    /// Intensidad relativa de la luz del tono por variante: en claro es menor que en oscuro para que la gráfica
    /// y los números manden sobre el fondo.
    static func intensity(for scheme: BackgroundScheme) -> Float {
        switch scheme {
        case .dark: 1
        case .light: 0.6
        }
    }

    /// Color sRGB efectivo de una arista a plena luz en la variante clara: la base teñida por la veladura del tono.
    static func lightVeilColor(for tone: GlucoseBackgroundTone) -> SIMD3<Float> {
        let k = Light.veil * intensity(for: .light)
        return simd_mix(Light.base, emission(for: tone), SIMD3(repeating: k))
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
