import SwiftUI

/// Filas de estado del sensor. `now` lo aporta el `TimelineView` de la pantalla.
struct SensorStatusSection: View {
    let status: SensorStatusSnapshot
    let now: Date

    var body: some View {
        Section {
            LabeledContent(String(localized: "sensor.row.state", defaultValue: "Estado")) {
                HStack(spacing: Tokens.Spacing.xs) {
                    Image(systemName: status.state.systemImage)
                        .foregroundStyle(status.state.tint)
                        .accessibilityHidden(true)
                    Text(status.state.title)
                }
            }
            if let profile = status.profile {
                LabeledContent(String(localized: "sensor.row.family", defaultValue: "Familia")) {
                    Text(profile.family.displayName)
                }
                LabeledContent(String(localized: "sensor.row.warmup", defaultValue: "Calentamiento restante")) {
                    warmupValue(profile)
                }
                LabeledContent(String(localized: "sensor.row.days", defaultValue: "Días restantes")) {
                    daysValue(profile)
                }
                LabeledContent(String(localized: "sensor.row.lastConnection", defaultValue: "Última conexión")) {
                    lastConnectionValue(profile)
                }
                LabeledContent {
                    Text(profile.receiverIDPartial ?? placeholder)
                        .monospaced()
                } label: {
                    Text(verbatim: "Receiver ID")
                }
            }
        } header: {
            Text(String(localized: "sensor.section.status", defaultValue: "Estado"))
        } footer: {
            if status.profile?.synthetic == true {
                Text(String(localized: "sensor.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real."))
            }
        }
    }

    private var placeholder: String {
        String(localized: "sensor.placeholder.value", defaultValue: "—")
    }

    @ViewBuilder
    private func warmupValue(_ profile: SensorPresentationProfile) -> some View {
        if let remaining = profile.warmupRemaining(at: now) {
            RemainingDurationText(duration: remaining)
        } else if profile.warmupEndsAt != nil {
            Text(String(localized: "sensor.warmup.done", defaultValue: "Completado"))
        } else {
            Text(placeholder)
        }
    }

    @ViewBuilder
    private func daysValue(_ profile: SensorPresentationProfile) -> some View {
        if let days = profile.daysRemaining(at: now) {
            Text(String(localized: "sensor.days.remaining", defaultValue: "\(days) días"))
                .monospacedDigit()
        } else {
            Text(placeholder)
        }
    }

    @ViewBuilder
    private func lastConnectionValue(_ profile: SensorPresentationProfile) -> some View {
        if let lastConnection = profile.lastConnection {
            Text(lastConnection, format: .relative(presentation: .named, unitsStyle: .wide))
        } else {
            Text(placeholder)
        }
    }
}
