import Foundation
import Testing
@testable import LingoScan

/// T-27b: calidad del fondo animado según tier, estado térmico y Low Power.
struct RenderQualityTests {
    @Test func nominalTiers() {
        #expect(RenderQuality.resolve(tier: .high, thermal: .nominal, lowPower: false)
            == RenderQuality(fps: 60, scale: 2, intensity: 1))
        #expect(RenderQuality.resolve(tier: .medium, thermal: .nominal, lowPower: false)
            == RenderQuality(fps: 60, scale: 2, intensity: 1))
        #expect(RenderQuality.resolve(tier: .low, thermal: .nominal, lowPower: false)
            == RenderQuality(fps: 30, scale: 1.5, intensity: 0.95))
    }

    @Test func fairThermalKeepsFrameRate() {
        #expect(RenderQuality.resolve(tier: .high, thermal: .fair, lowPower: false).fps == 60)
    }

    @Test func seriousThermalDegrades() {
        let quality = RenderQuality.resolve(tier: .high, thermal: .serious, lowPower: false)
        #expect(quality.fps == 30)
        #expect(quality.scale == 1.5)
        #expect(quality.intensity < 1)
    }

    @Test func criticalThermalDropsToTenFPS() {
        let quality = RenderQuality.resolve(tier: .high, thermal: .critical, lowPower: false)
        #expect(quality.fps == 10)
        #expect(quality.scale == 1)
    }

    @Test(arguments: [RenderQuality.DeviceTier.high, .medium, .low])
    func lowPowerCapsFrameRateAndScale(tier: RenderQuality.DeviceTier) {
        let quality = RenderQuality.resolve(tier: tier, thermal: .nominal, lowPower: true)
        #expect(quality.fps <= 30)
        #expect(quality.scale <= 1.5)
    }

    @Test func lowPowerNeverRaisesCriticalFrameRate() {
        let quality = RenderQuality.resolve(tier: .high, thermal: .critical, lowPower: true)
        #expect(quality.fps == 10)
        #expect(quality.scale == 1)
    }

    @Test func scaleNeverExceedsTwo() {
        for tier in [RenderQuality.DeviceTier.high, .medium, .low] {
            for thermal in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
                for lowPower in [false, true] {
                    #expect(RenderQuality.resolve(tier: tier, thermal: thermal, lowPower: lowPower).scale <= 2)
                }
            }
        }
    }

    @Test func missingDeviceIsLowTier() {
        #expect(RenderQuality.deviceTier(nil) == .low)
    }
}
