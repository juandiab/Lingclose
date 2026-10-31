import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Observa los toques de la ventana sin reconocer nunca: no cancela, no retrasa ni bloquea a SwiftUI,
/// los scroll views ni otros gestos. Solo sigue al primer dedo.
final class TouchObserver: UIGestureRecognizer {
    var onEvent: ((UITouch, PointerEvent.Phase, Bool) -> Void)?
    private var tracked: UITouch?
    private var start: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var travelled = false

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard tracked == nil, let touch = touches.first else { return }
        tracked = touch
        start = touch.location(in: nil)
        startTime = touch.timestamp
        travelled = false
        onEvent?(touch, .began, false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let tracked, touches.contains(tracked) else { return }
        let p = tracked.location(in: nil)
        if hypot(p.x - start.x, p.y - start.y) > 10 { travelled = true }
        onEvent?(tracked, .moved, false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if let tracked, touches.contains(tracked) {
            let isTap = !travelled && tracked.timestamp - startTime < 0.35
            onEvent?(tracked, .ended, isTap)
            self.tracked = nil
        }
        if allTouchesEnded(event) { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if let tracked, touches.contains(tracked) {
            onEvent?(tracked, .cancelled, false)
            self.tracked = nil
        }
        if allTouchesEnded(event) { state = .failed }
    }

    override func reset() {
        super.reset()
        tracked = nil
    }

    private func allTouchesEnded(_ event: UIEvent) -> Bool {
        (event.allTouches ?? []).allSatisfy { $0.phase == .ended || $0.phase == .cancelled }
    }
}
