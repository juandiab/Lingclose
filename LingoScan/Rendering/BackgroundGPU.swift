import Metal

/// Recursos Metal compartidos por los renderers del fondo.
@MainActor
final class BackgroundGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let pixelFormat: MTLPixelFormat = .bgra8Unorm
    /// Triángulo del color de estudio con alpha (fundido entre renderers).
    let fadePipeline: MTLRenderPipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.library = library
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Background fade"
        descriptor.vertexFunction = library.makeFunction(name: "bgFullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bgFadeFragment")
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = pixelFormat
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let fade = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        fadePipeline = fade
        queue.label = "Background"
    }

    func pipeline(vertex: String, fragment: String, format: MTLPixelFormat? = nil, label: String) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0]?.pixelFormat = format ?? pixelFormat
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func texture(width: Int, height: Int, format: MTLPixelFormat, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(1, width), height: max(1, height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    /// Pone a cero texturas recién creadas (los ping-pong leen el frame anterior).
    func clear(_ textures: [MTLTexture], in commandBuffer: MTLCommandBuffer) {
        for texture in textures {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }
    }
}
