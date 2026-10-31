// Hex Vault: rejilla hexagonal iluminada por una luz que sigue al dedo (autoplay cuando no se toca),
// con estela fluida a baja resolución, pulsos al tocar y shimmer. Port de JPLights con intensidad atenuada:
// en LingoScan el color sale del tono de glucosa y el fondo nunca compite con la curva.

import Metal
import simd
import CoreGraphics

private struct VaultTrailUniforms {
    var canvas = SIMD4<Float>.zero
    var segment = SIMD4<Float>.zero
    var brush = SIMD4<Float>.zero
    var timing = SIMD4<Float>.zero
    var decay = SIMD4<Float>.zero
}

private struct VaultCompositeUniforms {
    var frame = SIMD4<Float>.zero
    var lens = SIMD4<Float>.zero
    var shape = SIMD4<Float>.zero
    var look = SIMD4<Float>.zero
    var look2 = SIMD4<Float>.zero
    var colorA = SIMD4<Float>.zero
    var colorB = SIMD4<Float>.zero
    var background = SIMD4<Float>.zero
    var pulse0 = SIMD4<Float>.zero
    var pulse1 = SIMD4<Float>.zero
    var pulse2 = SIMD4<Float>.zero
    var pulse3 = SIMD4<Float>.zero
}

@MainActor
final class HexVaultRenderer: BackgroundRenderer {
    /// Parámetros del look (valores por defecto de la referencia; la rejilla se mantiene discreta).
    struct Look {
        var cellPoints: Float = 72 * 1.9 * 0.6   // la referencia mide en px CSS de escritorio; en iPhone, ~82 pt
        var lineWidth: Float = 0.5
        var litWidth: Float = 1.8
        var lattice: Float = 0.4
        var glow: Float = 1.5
        var glowRadius: Float = 0.5
        var core: Float = 0.4
        var grain: Float = 1
        var trailLength: Float = 3
        var trailWidth: Float = 1
        var follow: Float = 0.5
        var flow: Float = 0.5
        var shimmer: Float = 1
        var speed: Float = 1
        var pulseSpeed: Float = 1
        /// Intensidad global de la emisión (JPLights = 1). App de salud: legibilidad primero.
        var intensity: Float = 0.55
        static let background = VaultPalette.linear(SIMD3(repeating: 10.0 / 255))
    }

    private let gpu: BackgroundGPU
    private let look = Look()
    private let velocityPipeline: MTLRenderPipelineState
    private let lightPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var velocity: [MTLTexture] = []
    private var light: [MTLTexture] = []
    private var ping = 0
    private var trailSize: (width: Int, height: Int) = (0, 0)
    private var needsClear = true
    private var staticCleared = false

    private var current = BackgroundPalette.idle.vault
    private var target = BackgroundPalette.idle.vault

    // Pincel (puntos, origen en el centro, y hacia abajo).
    private var time: Float = 0
    private var brush = SIMD2<Float>.zero
    private var brushVelocity = SIMD2<Float>.zero
    private var previousBrush = SIMD2<Float>.zero
    private var roam = SIMD2<Float>.zero
    private var roamClock: Float = 0
    private var finger: SIMD2<Float>?
    private var presence: Float = 0
    private var lensLevel: Float = 0
    private var energy: Float = 0
    private var viewSize = SIMD2<Float>(390, 844)
    private var pulses: [SIMD4<Float>] = Array(repeating: .zero, count: 4)
    private var nextPulse = 0

    init?(gpu: BackgroundGPU) {
        self.gpu = gpu
        guard let v = gpu.pipeline(vertex: "vaultFullscreenVertex", fragment: "vaultVelocityFragment", format: .rg16Float, label: "Vault velocity"),
              let l = gpu.pipeline(vertex: "vaultFullscreenVertex", fragment: "vaultLightFragment", format: .rg16Float, label: "Vault light"),
              let c = gpu.pipeline(vertex: "vaultFullscreenVertex", fragment: "vaultCompositeFragment", label: "Vault composite")
        else { return nil }
        velocityPipeline = v
        lightPipeline = l
        compositePipeline = c
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let s = gpu.device.makeSamplerState(descriptor: sd) else { return nil }
        sampler = s
    }

    func setPalette(_ palette: BackgroundPalette, immediate: Bool) {
        target = palette.vault
        if immediate { current = target }
    }

    var isSettled: Bool { current.isClose(to: target) }

    func pointer(_ event: PointerEvent) {
        let p = SIMD2<Float>(Float(event.location.x), Float(event.location.y)) - viewSize * 0.5
        switch event.phase {
        case .began, .moved:
            finger = p
        case .ended, .cancelled:
            finger = nil
            roam = brush
            if event.isTap {
                pulses[nextPulse] = SIMD4(p.x, p.y, time, 1)
                nextPulse = (nextPulse + 1) % pulses.count
            }
        }
    }

    // MARK: Simulación del pincel (CPU)

    private func stepBrush(dt: Float) {
        roamClock += dt
        let target: SIMD2<Float>
        if let finger {
            target = finger
        } else {
            // Autoplay: rumbo con tres senos; si sale del 70 % del área, vuelve hacia el centro.
            let t = roamClock
            let heading = 0.18 * t + 1.25 * sin(t * 0.43) + 0.85 * sin(t * 0.27 + 1.7) + 0.55 * sin(t * 0.71 + 0.4)
            var dir = SIMD2<Float>(cos(heading), sin(heading))
            let half = viewSize * 0.5 * 0.7
            if abs(roam.x) > half.x || abs(roam.y) > half.y {
                let home = simd_normalize(-roam)
                dir = simd_normalize(simd_mix(dir, home, SIMD2(repeating: 0.85)))
            }
            let cruise = look.cellPoints * 1.1 * (0.8 + 0.2 * sin(t * 0.37)) * look.speed
            roam += dir * cruise * dt
            target = roam
        }
        // Muelle críticamente amortiguado (sub-pasos de 8 ms).
        let omega = 10 * look.follow
        let damping = 1.24 * omega
        var remaining = dt
        while remaining > 0 {
            let h = min(remaining, 0.008)
            let accel = omega * omega * (target - brush) - damping * brushVelocity
            brushVelocity += accel * h
            brush += brushVelocity * h
            remaining -= h
        }
        let speed = simd_length(brushVelocity)
        let wanted = 1 - exp(-speed / 120)
        let tau: Float = wanted > energy ? 0.08 : 0.35
        energy += (wanted - energy) * (1 - exp(-dt / tau))
        presence += (1 - presence) * (1 - exp(-dt / 0.3))
        let lensWanted: Float = finger != nil ? 1 : 0.78
        lensLevel += (lensWanted - lensLevel) * (1 - exp(-dt / 0.25))
    }

    // MARK: Texturas

    private func ensureTextures(drawable: CGSize, cellPx: Float) {
        let texel = max(cellPx / 20, 2)
        let w = max(8, Int((Float(drawable.width) / texel).rounded(.up)))
        let h = max(8, Int((Float(drawable.height) / texel).rounded(.up)))
        guard w != trailSize.width || h != trailSize.height || velocity.isEmpty else { return }
        trailSize = (w, h)
        velocity = (0..<2).compactMap { gpu.texture(width: w, height: h, format: .rg16Float, label: "Vault velocity \($0)") }
        light = (0..<2).compactMap { gpu.texture(width: w, height: h, format: .rg16Float, label: "Vault light \($0)") }
        needsClear = true
    }

    // MARK: Frame

    func encode(commandBuffer: MTLCommandBuffer, target pass: MTLRenderPassDescriptor, frame: BackgroundFrame) {
        let scale = Float(frame.scale)
        let dt = frame.dt
        let res = SIMD2<Float>(Float(frame.drawableSize.width), Float(frame.drawableSize.height))
        viewSize = res / max(scale, 0.5)
        let cellPx = look.cellPoints * scale
        ensureTextures(drawable: frame.drawableSize, cellPx: cellPx)
        guard velocity.count == 2, light.count == 2 else { return }
        if needsClear {
            gpu.clear(velocity + light, in: commandBuffer)
            needsClear = false
        }

        let animated = frame.motion > 0
        if animated {
            time += dt
            current = current.mixed(toward: target, amount: 1 - exp(-dt / 0.5))
            previousBrush = brush
            stepBrush(dt: dt)
            staticCleared = false
        } else {
            // Reduce Motion: rejilla quieta, luz fija en el centro, sin estela ni pulsos.
            current = target
            brush = .zero; previousBrush = .zero; brushVelocity = .zero
            presence = 1; lensLevel = 1; energy = 0
            pulses = Array(repeating: .zero, count: 4)
            if !staticCleared {
                gpu.clear(velocity + light, in: commandBuffer)
                staticCleared = true
            }
        }

        let radius = look.trailWidth * 2 * cellPx
        let wake = radius * (0.35 + 0.25 * energy)

        if animated {
            var tu = VaultTrailUniforms()
            tu.canvas = SIMD4(res.x, res.y, Float(trailSize.width), Float(trailSize.height))
            tu.segment = SIMD4(previousBrush.x * scale, previousBrush.y * scale, brush.x * scale, brush.y * scale)
            tu.brush = SIMD4(brushVelocity.x * scale, brushVelocity.y * scale, radius * 0.6,
                             (1 - exp(-dt / 0.05)) * presence)
            let fade = look.trailLength * 0.26
            tu.timing = SIMD4(dt, exp(-dt / 0.25), look.flow * 0.8, presence * 0.7)
            tu.decay = SIMD4(exp(-dt / fade), exp(-dt / (fade * 0.5)), wake, 0)

            let src = ping, dst = 1 - ping
            trailPass(commandBuffer, pipeline: velocityPipeline, target: velocity[dst], uniforms: &tu,
                      textures: [velocity[src]], label: "Vault velocity")
            trailPass(commandBuffer, pipeline: lightPipeline, target: light[dst], uniforms: &tu,
                      textures: [velocity[dst], light[src]], label: "Vault light")
            ping = dst
        }

        var cu = VaultCompositeUniforms()
        cu.frame = SIMD4(res.x, res.y, time * look.speed, time)
        cu.lens = SIMD4(brush.x * scale, brush.y * scale, presence * lensLevel, cellPx * 1.15)
        cu.shape = SIMD4(cellPx, look.lineWidth * scale, look.litWidth * scale, 0.8 * scale)
        cu.look = SIMD4(look.lattice, look.glow, look.glowRadius * scale, look.shimmer)
        cu.look2 = SIMD4(look.core, look.grain, look.pulseSpeed * 5.5 * cellPx, look.intensity * frame.quality.intensity)
        cu.colorA = SIMD4(current.colorA, 1)
        cu.colorB = SIMD4(current.colorB, 1)
        cu.background = SIMD4(Look.background, 1)
        let px = pulses.map { SIMD4($0.x * scale, $0.y * scale, $0.z, $0.w) }
        cu.pulse0 = px[0]; cu.pulse1 = px[1]; cu.pulse2 = px[2]; cu.pulse3 = px[3]

        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Vault composite"
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentBytes(&cu, length: MemoryLayout<VaultCompositeUniforms>.stride, index: 0)
        enc.setFragmentTexture(light[ping], index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func trailPass(_ cb: MTLCommandBuffer, pipeline: MTLRenderPipelineState, target: MTLTexture,
                           uniforms: inout VaultTrailUniforms, textures: [MTLTexture], label: String) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = label
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<VaultTrailUniforms>.stride, index: 0)
        for (i, t) in textures.enumerated() { enc.setFragmentTexture(t, index: i) }
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
