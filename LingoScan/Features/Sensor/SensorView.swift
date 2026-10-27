import SwiftUI

/// Pantalla provisional de Sensor (T-06).
struct SensorView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "sensor.title", defaultValue: "Sensor"),
                systemImage: "sensor.tag.radiowaves.forward",
                description: Text(String(localized: "sensor.placeholder", defaultValue: "Aquí verás el estado de tu sensor."))
            )
            .navigationTitle(String(localized: "sensor.title", defaultValue: "Sensor"))
        }
    }
}

#Preview {
    SensorView()
}
