import SwiftUI

/// "hace 2 min" / "ahora". Los minutos los calcula el view model con el reloj inyectado.
struct AgeText: View {
    let minutes: Int

    var body: some View {
        if minutes < 1 {
            Text(String(localized: "today.age.now", defaultValue: "ahora"))
        } else {
            let duration = Text(Duration.seconds(minutes * 60), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
            Text("today.age \(duration)")
        }
    }
}
