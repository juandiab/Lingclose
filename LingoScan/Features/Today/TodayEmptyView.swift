import SwiftUI

/// Hoy sin lecturas guardadas: explica el estado del sensor. El chip de arriba lleva a Sensor.
struct TodayEmptyView: View {
    let sensor: SensorStatusSnapshot

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "today.empty.title", defaultValue: "Sin lecturas todavía"),
                systemImage: sensor.state.systemImage
            )
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.lg)
    }

    private var description: String {
        switch sensor.state {
        case .noSensor, .identified, .incompatible, .readyToActivate:
            String(localized: "today.empty.noSensor", defaultValue: "Estado del sensor: \(sensor.state.title). Toca el estado de arriba para leer o activar un sensor.")
        case .warmingUp:
            String(localized: "today.empty.warmingUp", defaultValue: "El sensor está calentando. Las lecturas aparecerán al terminar.")
        default:
            String(localized: "today.empty.state", defaultValue: "Estado del sensor: \(sensor.state.title). Las lecturas aparecerán aquí en cuanto lleguen.")
        }
    }
}

#Preview {
    TodayEmptyView(sensor: .noSensor)
}
