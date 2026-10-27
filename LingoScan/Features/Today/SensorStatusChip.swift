import SwiftUI

/// Chip de estado del sensor. Navega a la pantalla Sensor desde la pila de Hoy.
struct SensorStatusChip: View {
    let state: SensorPresentationState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer {
            NavigationLink(value: TodayRoute.sensor) {
                GlassChip(
                    title: state.title,
                    systemImage: state.systemImage,
                    iconTint: state.tint,
                    isPulsing: state == .reconnecting && !reduceMotion
                )
            }
            .buttonStyle(.plain)
        }
        .accessibilityHint(String(localized: "today.sensorChip.hint", defaultValue: "Abre el estado del sensor"))
    }
}

#Preview {
    NavigationStack {
        SensorStatusChip(state: .streaming)
            .navigationDestination(for: TodayRoute.self) { _ in Text(verbatim: "Sensor") }
    }
}
