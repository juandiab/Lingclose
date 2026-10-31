import Metal

/// Contrato común de los fondos animados. Un único `MTKView` (`BackgroundEngine`) aloja al renderer activo;
/// cambiar de fondo cambia el renderer dentro del mismo host con un fundido, sin recrear la vista.
@MainActor
protocol BackgroundRenderer: AnyObject {
    /// Nueva paleta objetivo. `immediate` salta la interpolación (Reduce Motion, primer frame).
    func setPalette(_ palette: BackgroundPalette, immediate: Bool)
    /// `true` cuando no queda nada por animar (paleta convergida). Solo se usa con Reduce Motion.
    var isSettled: Bool { get }
    func pointer(_ event: PointerEvent)
    /// Codifica todas sus pasadas; la última debe escribir `target` (color 0 = drawable).
    func encode(commandBuffer: MTLCommandBuffer, target: MTLRenderPassDescriptor, frame: BackgroundFrame)
}

extension BackgroundRenderer {
    func pointer(_ event: PointerEvent) {}
}
