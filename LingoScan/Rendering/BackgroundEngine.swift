// Host único de los fondos: un MTKView, un renderer activo y las reglas de energía (port de JPLights).
//
//  · Pausa: fuera de la ventana, app no activa (background / multitarea) → `isPaused` + `releaseDrawables`.
//  · Calidad: tier del dispositivo × `thermalState` × Low Power → fps, escala del drawable y densidad.
//  · Reduce Motion: sin display link; un redibujo bajo demanda (máx. 1 por segundo) cuando cambia la paleta.
//  · Cambio de fondo: fundido al color de estudio (0,28 s) → nuevo renderer → fundido de entrada (0,4 s).

import MetalKit
import UIKit
import os

@MainActor
final class BackgroundEngine: NSObject, MTKViewDelegate {
    let gpu: BackgroundGPU
    private weak var view: MTKView?

    private(set) var style: BackgroundStyle
    private var renderer: BackgroundRenderer?
    private var pendingStyle: BackgroundStyle?
    /// 0 = negro, 1 = renderer a plena vista.
    private var visibility: Float = 0
    private var palette = BackgroundPalette.idle

    private var reduceMotion = false
    private var isActive = true
    private var inWindow = false

    private let tier: RenderQuality.DeviceTier
    private(set) var quality: RenderQuality
    private var lastTimestamp: CFTimeInterval?
    private var frameIndex: UInt32 = 0
    private var lastStaticDraw: CFTimeInterval = 0
    private var staticRedrawScheduled = false
    private var monitors: [Task<Void, Never>] = []
    /// Frames en vuelo en la GPU. Si los dos están ocupados se salta el frame en vez de esperar un drawable:
    /// `currentDrawable` bloquea el hilo principal (hasta 1 s) cuando la GPU o el compositor van tarde, y ese
    /// bloqueo congela también la UI. Mejor un frame de fondo menos que un tirón en el scroll.
    private let inFlight = DispatchSemaphore(value: 2)

    #if DEBUG
    private let log = Logger(subsystem: "com.otalvaro.lingoscan", category: "Background")
    private var statFrames = 0
    private var statEncode: CFTimeInterval = 0
    private var statStart: CFTimeInterval = 0
    private var statSkipped = 0
    private var statAcquire: CFTimeInterval = 0
    #endif

    init?(style: BackgroundStyle) {
        guard let gpu = BackgroundGPU() else { return nil }
        self.gpu = gpu
        self.style = style
        tier = RenderQuality.deviceTier(gpu.device)
        quality = RenderQuality.resolve(tier: tier, thermal: ProcessInfo.processInfo.thermalState,
                                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        super.init()
        renderer = makeRenderer(style)
        #if DEBUG
        log.info("start: tier \(String(describing: self.tier)), thermal \(ProcessInfo.processInfo.thermalState.rawValue), lowPower \(ProcessInfo.processInfo.isLowPowerModeEnabled), \(self.quality.fps) fps, scale \(Double(self.quality.scale))")
        #endif
        monitors.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ProcessInfo.thermalStateDidChangeNotification) {
                self?.refreshQuality()
            }
        })
        monitors.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                self?.refreshQuality()
            }
        })
        monitors.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                self?.setActive(false)
            }
        })
    }

    isolated deinit {
        monitors.forEach { $0.cancel() }
    }

    // MARK: Vista

    func attach(to view: MTKView) {
        self.view = view
        view.device = gpu.device
        view.colorPixelFormat = gpu.pixelFormat
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0.0392, green: 0.0392, blue: 0.0392, alpha: 1)
        view.isOpaque = true
        view.backgroundColor = UIColor(red: 0.0392, green: 0.0392, blue: 0.0392, alpha: 1)
        view.autoResizeDrawable = true
        view.presentsWithTransaction = false
        view.delegate = self
        applyQuality()
        updateRunState()
    }

    func windowDidChange(inWindow: Bool) {
        self.inWindow = inWindow
        if inWindow { applyQuality() }
        updateRunState()
        requestStaticRedraw()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        updateRunState()
        if active { requestStaticRedraw() }
    }

    func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        lastTimestamp = nil
        renderer?.setPalette(palette, immediate: on)
        updateRunState()
        requestStaticRedraw()
    }

    func setPalette(_ new: BackgroundPalette) {
        guard new != palette else { return }
        palette = new
        renderer?.setPalette(new, immediate: reduceMotion)
        requestStaticRedraw()
    }

    func setStyle(_ new: BackgroundStyle) {
        guard new != (pendingStyle ?? style) else { return }
        if reduceMotion || renderer == nil && visibility == 0 {
            swap(to: new)
            visibility = 1
            updateRunState()
            requestStaticRedraw()
            return
        }
        pendingStyle = new
        updateRunState()
    }

    func pointer(_ event: PointerEvent) {
        guard !reduceMotion else { return }
        renderer?.pointer(event)
    }

    // MARK: Estado

    private func makeRenderer(_ style: BackgroundStyle) -> BackgroundRenderer? {
        let r: BackgroundRenderer?
        switch style {
        case .hexVault: r = HexVaultRenderer(gpu: gpu)
        case .none: r = nil
        }
        r?.setPalette(palette, immediate: true)
        return r
    }

    private func swap(to new: BackgroundStyle) {
        style = new
        pendingStyle = nil
        renderer = makeRenderer(new)
    }

    /// Sin nada que mostrar (None ya fundido) no hace falta display link.
    private var isIdleBlack: Bool { renderer == nil && pendingStyle == nil && visibility <= 0 }

    private func updateRunState() {
        guard let view else { return }
        let canRun = inWindow && isActive
        if !canRun {
            view.isPaused = true
            view.enableSetNeedsDisplay = false
            if !isActive { view.releaseDrawables() }
            lastTimestamp = nil
            return
        }
        if reduceMotion || isIdleBlack {
            view.enableSetNeedsDisplay = true
            view.isPaused = true
            lastTimestamp = nil
        } else {
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
    }

    /// Reduce Motion: como mucho un redibujo por segundo cuando cambia algo.
    private func requestStaticRedraw() {
        guard let view, view.isPaused, inWindow, isActive, !staticRedrawScheduled else { return }
        let now = CACurrentMediaTime()
        let wait = max(0, 1 - (now - lastStaticDraw))
        if wait == 0 {
            view.setNeedsDisplay()
            return
        }
        staticRedrawScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self else { return }
            self.staticRedrawScheduled = false
            if let view = self.view, view.isPaused, self.inWindow, self.isActive { view.setNeedsDisplay() }
        }
    }

    private func refreshQuality() {
        let q = RenderQuality.resolve(tier: tier, thermal: ProcessInfo.processInfo.thermalState,
                                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard q != quality else { return }
        quality = q
        applyQuality()
        #if DEBUG
        log.info("quality → \(q.fps) fps, scale \(Double(q.scale))")
        #endif
    }

    private func applyQuality() {
        guard let view else { return }
        view.preferredFramesPerSecond = quality.fps
        let screenScale = view.window?.screen.scale ?? view.traitCollection.displayScale
        view.contentScaleFactor = min(quality.scale, max(screenScale, 1))
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestStaticRedraw()
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else {
            #if DEBUG
            statSkipped += 1
            #endif
            // Con Reduce Motion no hay display link: reprograma el redibujo que se ha saltado.
            if view.isPaused { requestStaticRedraw() }
            return
        }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - (lastTimestamp ?? now - 1.0 / 60), 0), 0.1))
        lastTimestamp = reduceMotion ? nil : now
        if reduceMotion { lastStaticDraw = now }

        // Fundido entre renderers (con Reduce Motion, cambio directo).
        if reduceMotion {
            if let pendingStyle { swap(to: pendingStyle) }
            visibility = renderer != nil ? 1 : 0
        } else if let pendingStyle {
            visibility = max(0, visibility - dt / 0.28)
            if visibility == 0 { swap(to: pendingStyle) }
        } else if visibility < 1, renderer != nil {
            visibility = min(1, visibility + dt / 0.4)
        }

        #if DEBUG
        let acquireStart = CACurrentMediaTime()
        #endif
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = gpu.queue.makeCommandBuffer() else { return }
        #if DEBUG
        statAcquire += CACurrentMediaTime() - acquireStart
        #endif
        commandBuffer.label = "Background frame"
        frameIndex &+= 1

        let frame = BackgroundFrame(drawableSize: view.drawableSize, scale: view.contentScaleFactor,
                                    dt: reduceMotion ? 0 : dt, motion: reduceMotion ? 0 : 1,
                                    frameIndex: frameIndex, quality: quality)
        #if DEBUG
        let t0 = CACurrentMediaTime()
        #endif
        if let renderer, visibility > 0 {
            renderer.encode(commandBuffer: commandBuffer, target: pass, frame: frame)
            if visibility < 1 {
                pass.colorAttachments[0].loadAction = .load
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                    var alpha = 1 - smoothstep(visibility)
                    enc.setRenderPipelineState(gpu.fadePipeline)
                    enc.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    enc.endEncoding()
                }
            }
        } else {
            pass.colorAttachments[0].loadAction = .clear
            commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }
        commandBuffer.present(drawable)
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        commandBuffer.commit()
        committed = true

        #if DEBUG
        statFrames += 1
        statEncode += CACurrentMediaTime() - t0
        if statStart == 0 { statStart = now }
        if now - statStart >= 5 {
            let fps = Double(statFrames) / (now - statStart)
            let ms = statEncode / Double(statFrames) * 1000
            let acquire = statAcquire / Double(statFrames) * 1000
            log.info("\(self.style.rawValue): \(fps, format: .fixed(precision: 1)) fps, encode \(ms, format: .fixed(precision: 2)) ms, drawable wait \(acquire, format: .fixed(precision: 2)) ms, skipped \(self.statSkipped), \(Int(view.drawableSize.width))x\(Int(view.drawableSize.height)) px")
            statFrames = 0; statEncode = 0; statStart = now; statSkipped = 0; statAcquire = 0
        }
        #endif

        // None ya en negro / Reduce Motion asentado → parar el display link.
        if isIdleBlack { updateRunState() }
        if reduceMotion, let renderer, !renderer.isSettled { requestStaticRedraw() }
    }

    private func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
