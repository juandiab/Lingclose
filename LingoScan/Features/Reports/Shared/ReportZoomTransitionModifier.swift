import SwiftUI

/// Zoom desde la card al detalle; con Reduce Motion, la transición estándar.
struct ReportZoomTransitionModifier: ViewModifier {
    let route: ReportRoute
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: route, in: namespace))
        }
    }
}
