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
            if let note = status.note {
                Text(note)
                    .foregroundStyle(.secondary)
            }
            if let failure = status.failure {
                LabeledContent(String(localized: "sensor.row.failurePhase", defaultValue: "Fase")) {
                    Text(failure.phase)
                }
                Text(failure.summary)
                    .foregroundStyle(.secondary)
                if failure.isIncompleteAttempt {
                    Label(
                        String(localized: "sensor.failure.incomplete", defaultValue: "Intento de activación incompleto. No se reenvía nada automáticamente; investiga antes de usar otro sensor."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Tokens.Palette.error)
                } else if failure.isInterruption {
                    Text(String(localized: "sensor.failure.interrupted", defaultValue: "Fue un corte o un tiempo agotado: no indica credenciales equivocadas."))
                        .foregroundStyle(.secondary)
                }
            }
            if let profile = status.profile {
                LabeledContent(String(localized: "sensor.row.family", defaultValue: "Familia")) {
                    Text(profile.family.displayName)
                }
                LabeledContent {
                    Text(profile.productType, format: .number.grouping(.never))
                        .monospacedDigit()
                } label: {
                    Text(verbatim: "productType")
                }
                LabeledContent {
                    Text(profile.securityVersion, format: .number.grouping(.never))
                        .monospacedDigit()
                } label: {
                    Text(verbatim: "securityVersion")
                }
                if let serial = profile.serialRedacted {
                    LabeledContent(String(localized: "sensor.row.serial", defaultValue: "Serial")) {
                        Text(serial)
                            .monospaced()
                    }
                }
                if let stateByte = profile.stateByte {
                    LabeledContent {
                        Text(stateByte, format: .number.grouping(.never))
                            .monospacedDigit()
                    } label: {
                        Text(String(localized: "sensor.row.stateByte", defaultValue: "Estado del parche (NFC)"))
                    }
                }
                if let warmup = profile.warmupMinutes {
                    LabeledContent(String(localized: "sensor.row.warmupDeclared", defaultValue: "Calentamiento declarado")) {
                        RemainingDurationText(duration: .seconds(warmup * 60))
                    }
                }
                if let wear = profile.wearMinutes {
                    LabeledContent(String(localized: "sensor.row.wearDeclared", defaultValue: "Duración declarada")) {
                        RemainingDurationText(duration: .seconds(wear * 60))
                    }
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
