import UIKit

/// Ranura UIKit donde se aloja el `MTKView` compartido mientras está en una ventana.
final class BackgroundSlotView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Color de estudio de la variante (claro u oscuro) hasta que se aloja el `MTKView`.
        backgroundColor = UIColor { trait in
            let c = (trait.userInterfaceStyle == .light ? BackgroundScheme.light : .dark).studioColor
            return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        }
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
