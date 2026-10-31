import MetalKit
import UIKit

/// `MTKView` que avisa al engine al entrar/salir de la ventana y observa el dedo en toda la ventana.
final class BackgroundMTKView: MTKView {
    var engine: BackgroundEngine?
    private let touches = TouchObserver()
    private weak var observedWindow: UIWindow?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        touches.onEvent = { [weak self] touch, phase, isTap in
            guard let self else { return }
            self.engine?.pointer(PointerEvent(phase: phase, location: touch.location(in: self), isTap: isTap))
        }
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if observedWindow !== window {
            observedWindow?.removeGestureRecognizer(touches)
            window?.addGestureRecognizer(touches)
            observedWindow = window
        }
        engine?.windowDidChange(inWindow: window != nil)
    }
}
