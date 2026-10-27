import SwiftUI

/// Duración restante en unidades legibles ("42 min", "1 h 5 min").
struct RemainingDurationText: View {
    let duration: Duration

    var body: some View {
        Text(duration, format: .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}
