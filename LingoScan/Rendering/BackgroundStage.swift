import UIKit

/// Un único `MTKView` + engine para toda la app (port de JPLights).
///
/// El contenedor del `TabView` de iOS 26 es opaco: una capa detrás del TabView no se ve. Por eso cada
/// pantalla declara una "ranura" (`appBackground()`) en su contenedor de navegación y el `MTKView` se
/// re-aloja en la ranura visible más reciente. El estado del fondo nunca se reinicia al cambiar de pestaña.
@MainActor
final class BackgroundStage {
    static let shared = BackgroundStage()

    let view: BackgroundMTKView
    let engine: BackgroundEngine?
    private var slots: [WeakSlot] = []

    private struct WeakSlot {
        weak var view: BackgroundSlotView?
    }

    private init() {
        view = BackgroundMTKView(frame: .zero, device: nil)
        let stored = UserDefaults.standard.string(forKey: BackgroundStyle.storageKey)
        engine = BackgroundEngine(style: BackgroundStyle(stored: stored))
        view.engine = engine
        engine?.attach(to: view)
    }

    func claim(_ slot: BackgroundSlotView) {
        slots.removeAll { $0.view == nil || $0.view === slot }
        slots.append(WeakSlot(view: slot))
        host(in: slot)
    }

    func release(_ slot: BackgroundSlotView) {
        slots.removeAll { $0.view == nil || $0.view === slot }
        guard view.superview === slot else { return }
        if let fallback = slots.last(where: { $0.view?.window != nil })?.view {
            host(in: fallback)
        } else {
            view.removeFromSuperview()
        }
    }

    private func host(in slot: BackgroundSlotView) {
        guard view.superview !== slot else { return }
        view.frame = slot.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        slot.addSubview(view)
    }
}
