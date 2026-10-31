import SwiftUI

/// Envuelve una card en un enlace a su detalle (con origen para la transición de zoom). Sin datos suficientes la
/// card no navega.
struct ReportCardLink<Label: View>: View {
    let route: ReportRoute
    let isEnabled: Bool
    let namespace: Namespace.ID
    @ViewBuilder let label: Label

    var body: some View {
        if isEnabled {
            NavigationLink(value: route) {
                label
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: route, in: namespace)
        } else {
            label
        }
    }
}
