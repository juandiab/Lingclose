import CoreGraphics
import Foundation
import Metal

/// Calidad adaptativa del fondo: tier del dispositivo × estado térmico × Low Power → fps, escala e intensidad.
///
/// El fondo es decoración: ante calor o ahorro de energía cede primero (menos fps y resolución).
struct RenderQuality: Equatable, Sendable {
    /// `preferredFramesPerSecond` del `MTKView`.
    var fps: Int
    /// Factor de escala del drawable (px por pt). La rejilla es suave: no hace falta 3×.
    var scale: CGFloat
    /// Intensidad relativa (baja un poco al degradar).
    var intensity: Float

    enum DeviceTier: Sendable {
        case high, medium, low
    }

    static func deviceTier(_ device: MTLDevice?) -> DeviceTier {
        guard let device else { return .low }
        #if targetEnvironment(simulator)
        return .medium
        #else
        if device.supportsFamily(.apple9) { return .high }      // A17 Pro / M3 y posteriores
        if device.supportsFamily(.apple7) { return .medium }    // A14 – A16
        return .low
        #endif
    }

    static func resolve(tier: DeviceTier, thermal: ProcessInfo.ThermalState, lowPower: Bool) -> RenderQuality {
        var quality: RenderQuality
        switch tier {
        case .high, .medium: quality = RenderQuality(fps: 60, scale: 2, intensity: 1)
        case .low: quality = RenderQuality(fps: 30, scale: 1.5, intensity: 0.95)
        }
        switch thermal {
        case .nominal, .fair:
            // `.fair` es habitual en uso normal (cargando, BLE activo): el coste del fondo es pequeño.
            break
        case .serious:
            quality.fps = min(quality.fps, 30)
            quality.scale = 1.5
            quality.intensity *= 0.9
        case .critical:
            quality.fps = 10
            quality.scale = 1
            quality.intensity *= 0.85
        @unknown default:
            break
        }
        if lowPower {
            quality.fps = min(quality.fps, 30)
            quality.scale = min(quality.scale, 1.5)
        }
        return quality
    }
}
