import UIKit

/// Ranura UIKit donde se aloja el `MTKView` compartido mientras está en una ventana.
final class BackgroundSlotView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.0392, green: 0.0392, blue: 0.0392, alpha: 1)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            BackgroundStage.shared.claim(self)
        } else {
            BackgroundStage.shared.release(self)
        }
    }
}
