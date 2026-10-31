import Foundation
import Testing
import simd
@testable import LingoScan

/// T-27b: tono y paleta del fondo según la última lectura y el rango de referencia del usuario.
struct GlucoseBackgroundPaletteTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tone(_ value: Int?, age: TimeInterval = 60, low: Int = 70, high: Int = 140) -> GlucoseBackgroundTone {
        GlucoseBackgroundTone.resolve(
            value: value, measuredAt: value == nil ? nil : now.addingTimeInterval(-age), now: now, low: low, high: high)
    }

    @Test func inRangeIncludesBothLines() {
        #expect(tone(70) == .inRange)
        #expect(tone(105) == .inRange)
        #expect(tone(140) == .inRange)
    }

    @Test func outsideTheLines() {
        #expect(tone(69) == .low)
        #expect(tone(141) == .high)
        #expect(tone(260) == .high)
    }

    @Test func followsUserRange() {
        #expect(tone(150, low: 70, high: 180) == .inRange)
        #expect(tone(75, low: 80, high: 180) == .low)
    }

    @Test func noReadingOrStaleIsNeutral() {
        #expect(tone(nil) == .neutral)
        #expect(tone(110, age: 300) == .inRange)
        #expect(tone(110, age: 301) == .neutral)
        #expect(tone(250, age: 3_600) == .neutral)
        let missingDate = GlucoseBackgroundTone.resolve(value: 110, measuredAt: nil, now: now, low: 70, high: 140)
        #expect(missingDate == .neutral)
    }

    @Test func palettesAreDistinctPerTone() {
        let palettes = GlucoseBackgroundTone.allCases.map { BackgroundPalette(tone: $0) }
        #expect(Set(palettes.map { "\($0.vault.colorA)" }).count == GlucoseBackgroundTone.allCases.count)
    }

    /// Nunca rojo: en ningún tono el rojo domina claramente sobre verde (alto es ámbar, no rojo).
    @Test func neverRed() {
        for tone in GlucoseBackgroundTone.allCases {
            let c = BackgroundPalette.emission(for: tone)
            #expect(c.y >= c.x * 0.6, "\(tone) demasiado rojo: \(c)")
        }
    }

    @Test func hueFamilies() {
        let inRange = BackgroundPalette.emission(for: .inRange)
        #expect(inRange.y > inRange.x && inRange.y > inRange.z)       // verde-teal
        let high = BackgroundPalette.emission(for: .high)
        #expect(high.x > high.y && high.y > high.z)                     // ámbar cálido
        let low = BackgroundPalette.emission(for: .low)
        #expect(low.z > low.x && low.z > low.y)                         // azul
        let neutral = BackgroundPalette.emission(for: .neutral)
        #expect(neutral.max() - neutral.min() < 0.1)                    // casi gris
    }

    @Test func neutralIsDimmest() {
        let neutralPeak = BackgroundPalette.emission(for: .neutral).max()
        for tone in [GlucoseBackgroundTone.inRange, .high, .low] {
            #expect(neutralPeak < BackgroundPalette.emission(for: tone).max())
        }
    }

    @Test func paletteIsLinearAndHighlightIsLighter() {
        let palette = BackgroundPalette(tone: .inRange)
        let srgb = BackgroundPalette.emission(for: .inRange)
        #expect(simd_length(palette.vault.colorA - VaultPalette.linear(srgb)) < 1e-6)
        #expect(palette.vault.colorB.sum() > palette.vault.colorA.sum())
    }

    @Test func linearConversionEndpoints() {
        #expect(VaultPalette.linear(.zero) == .zero)
        #expect(simd_length(VaultPalette.linear(.one) - .one) < 1e-5)
        #expect(abs(VaultPalette.linear(SIMD3(repeating: 0.5)).x - 0.214) < 0.001)
    }

    @Test func mixingConverges() {
        let a = BackgroundPalette(tone: .low).vault
        let b = BackgroundPalette(tone: .high).vault
        #expect(a.mixed(toward: b, amount: 1).isClose(to: b))
        #expect(!a.mixed(toward: b, amount: 0.5).isClose(to: b))
    }

    @Test func storedStyleFallsBackToDefault() {
        #expect(BackgroundStyle(stored: nil) == .hexVault)
        #expect(BackgroundStyle(stored: "rain") == .hexVault)
        #expect(BackgroundStyle(stored: "none") == BackgroundStyle.none)
        #expect(!BackgroundStyle.none.isAnimated)
        #expect(BackgroundStyle.hexVault.isAnimated)
    }
}

/// T-27b: con fondo animado la app va en oscuro; con "Ninguno" manda la apariencia elegida.
struct AppColorSchemeTests {
    @Test func animatedBackgroundForcesDark() {
        for appearance in AppearanceMode.allCases {
            #expect(AppColorSchemeModifier.colorScheme(style: .hexVault, appearance: appearance) == .dark)
        }
    }

    @Test func noneFollowsAppearance() {
        #expect(AppColorSchemeModifier.colorScheme(style: .none, appearance: .system) == nil)
        #expect(AppColorSchemeModifier.colorScheme(style: .none, appearance: .light) == .light)
        #expect(AppColorSchemeModifier.colorScheme(style: .none, appearance: .dark) == .dark)
    }
}
