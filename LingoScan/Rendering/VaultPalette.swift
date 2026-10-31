import simd

/// Colores de Hex Vault en sRGB lineal (el shader trabaja en lineal y codifica a sRGB al final).
/// `colorA` = aristas frías (la luz que recorre la rejilla) · `colorB` = la parte caliente de la estela.
struct VaultPalette: Equatable, Sendable {
    var colorA: SIMD3<Float>
    var colorB: SIMD3<Float>

    func mixed(toward target: VaultPalette, amount k: Float) -> VaultPalette {
        let t = SIMD3<Float>(repeating: k)
        return VaultPalette(colorA: simd_mix(colorA, target.colorA, t), colorB: simd_mix(colorB, target.colorB, t))
    }

    func isClose(to other: VaultPalette, tolerance: Float = 0.002) -> Bool {
        simd_length(colorA - other.colorA) <= tolerance && simd_length(colorB - other.colorB) <= tolerance
    }

    /// sRGB (0–1) → lineal.
    static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func f(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return SIMD3(f(c.x), f(c.y), f(c.z))
    }
}
