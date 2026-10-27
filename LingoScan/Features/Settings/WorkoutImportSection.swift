import SwiftUI

/// Ajustes → Salud: entrenamientos del Apple Watch importados desde Salud (solo lectura).
struct WorkoutImportSection: View {
    @Environment(\.workoutImport) private var trigger
    @State private var result: String?

    var body: some View {
        if let trigger {
            Section {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Label(String(localized: "workouts.settings.title", defaultValue: "Entrenamientos del Apple Watch"), systemImage: "applewatch")
                    Text(String(localized: "workouts.settings.auto", defaultValue: "Importa automáticamente al terminar un entrenamiento"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(String(localized: "workouts.settings.last", defaultValue: "Última importación")) {
                    if let at = trigger.status.lastImportAt {
                        Text(at, format: .relative(presentation: .named))
                    } else {
                        Text(String(localized: "workouts.settings.never", defaultValue: "Nunca"))
                    }
                }
                LabeledContent(String(localized: "workouts.settings.total", defaultValue: "Importados"), value: trigger.status.totalImported, format: .number)
                Button {
                    Task { result = Self.summary(await trigger.importNow()) }
                } label: {
                    HStack {
                        Label(String(localized: "workouts.settings.importNow", defaultValue: "Importar ahora"), systemImage: "arrow.down.circle")
                        if trigger.isImporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(trigger.isImporting)
                if let result {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "workouts.settings.header", defaultValue: "Salud"))
            } footer: {
                Text(String(localized: "workouts.settings.footer", defaultValue: "Solo lectura: LingoScan nunca escribe ejercicio en Salud. Los entrenamientos aparecen en el Diario y como marcas en Hoy."))
            }
            .task { await trigger.refreshStatus() }
        }
    }

    /// Texto breve del resultado de una importación (también lo usa el registro rápido).
    static func summary(_ report: WorkoutImportReport?) -> String {
        guard let report else {
            return String(localized: "workouts.result.failed", defaultValue: "No se pudo leer Salud.")
        }
        guard report.changed > 0 else {
            return String(localized: "workouts.result.none", defaultValue: "Sin entrenamientos nuevos.")
        }
        return String(localized: "workouts.result.counts",
                      defaultValue: "Nuevos: \(report.imported). Actualizados: \(report.updated).")
    }
}
