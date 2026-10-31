import SwiftUI

/// Puente SwiftUI de `BackgroundSlotView` (lo usa `AppBackgroundModifier`).
struct BackgroundSlot: UIViewRepresentable {
    func makeUIView(context: Context) -> BackgroundSlotView { BackgroundSlotView() }
    func updateUIView(_ uiView: BackgroundSlotView, context: Context) {}
}
