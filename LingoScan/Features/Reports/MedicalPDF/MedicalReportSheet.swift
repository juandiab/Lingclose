import SwiftUI

/// Hoja previa de "Reporte para el médico (PDF)" (T-34): nombre, período, secciones opcionales y "Generar PDF"; al
/// terminar muestra una vista previa y deja compartir el archivo. Los textos siguen Dynamic Type; el PDF, no.
struct MedicalReportSheet: View {
    @State private var viewModel: MedicalReportViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    init(content: ReportContent, isSynthetic: Bool, health: ReportAnalysisHealthSources, nutrition: any MealNutritionStore) {
        _viewModel = State(initialValue: MedicalReportViewModel(
            content: content, isSynthetic: isSynthetic, health: health, nutrition: nutrition))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .editing, .failed: form
                case .generating(let done, let total): progress(done: done, total: total)
                case .ready(let url): preview(url)
                }
            }
            .navigationTitle(String(localized: "reports.medical.title", defaultValue: "Reporte para el médico"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .ready = viewModel.phase {
                        Button(String(localized: "reports.medical.edit", defaultValue: "Editar"), action: viewModel.backToEditing)
                    } else {
                        Button(String(localized: "reports.medical.close", defaultValue: "Cerrar")) { dismiss() }
                    }
                }
                if case .ready(let url) = viewModel.phase {
                    ToolbarItem(placement: .confirmationAction) { shareLink(url) }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isGenerating)
        .onDisappear { viewModel.cancel() }
        .onChange(of: viewModel.phase) { _, phase in
            // El error aparece en el formulario sin mover el foco de VoiceOver: se anuncia.
            if phase == .failed {
                AccessibilityNotification.Announcement(
                    String(localized: "reports.medical.failed", defaultValue: "No se pudo generar el PDF. Inténtalo de nuevo.")
                ).post()
            }
        }
    }

    // MARK: Formulario

    private var form: some View {
        Form {
            Section {
                TextField(String(localized: "reports.medical.name.placeholder", defaultValue: "Tu nombre"), text: $viewModel.name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
            } header: {
                Text(String(localized: "reports.medical.name", defaultValue: "Nombre del paciente"))
            } footer: {
                Text(String(localized: "reports.medical.name.footer",
                            defaultValue: "Aparece en el encabezado de cada página del PDF. Se guarda solo en este iPhone; nunca va a los datos compartidos ni al análisis con IA. También lo puedes cambiar en Ajustes."))
            }

            Section {
                LabeledContent(String(localized: "reports.medical.period", defaultValue: "Período")) {
                    Text(viewModel.periodText).multilineTextAlignment(.trailing)
                }
            } footer: {
                Text(String(localized: "reports.medical.period.footer",
                            defaultValue: "Es el período que tienes elegido en Reportes. Para cambiarlo, cierra esta hoja y elígelo arriba."))
            }

            Section {
                toggle(String(localized: "reports.medical.section.meals", defaultValue: "Comidas"),
                       systemImage: "fork.knife", isOn: $viewModel.options.meals, hasData: viewModel.hasMeals)
                toggle(String(localized: "reports.medical.section.sleep", defaultValue: "Sueño y actividad"),
                       systemImage: "bed.double", isOn: $viewModel.options.sleepActivity, hasData: true)
                toggle(String(localized: "reports.medical.section.exercise", defaultValue: "Ejercicio"),
                       systemImage: "figure.run", isOn: $viewModel.options.exercise, hasData: viewModel.hasExercise)
                toggle(String(localized: "reports.medical.section.body", defaultValue: "Composición corporal"),
                       systemImage: "scalemass", isOn: $viewModel.options.bodyComposition, hasData: true)
                toggle(String(localized: "reports.medical.section.notes", defaultValue: "Notas del diario"),
                       systemImage: "note.text", isOn: $viewModel.options.notes, hasData: viewModel.hasNotes)
            } header: {
                Text(String(localized: "reports.medical.sections", defaultValue: "Secciones opcionales"))
            } footer: {
                Text(String(localized: "reports.medical.sections.footer",
                            defaultValue: "El resumen, el perfil de glucosa (AGP), los perfiles diarios, las franjas del día y la comparación semanal siempre van."))
            }

            Section {
                Button(action: generate) {
                    Label(String(localized: "reports.medical.generate", defaultValue: "Generar PDF"), systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if viewModel.phase == .failed {
                    Label(String(localized: "reports.medical.failed", defaultValue: "No se pudo generar el PDF. Inténtalo de nuevo."),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(String(localized: "reports.medical.health.footer",
                            defaultValue: "Al generar, Lingclose lee de Apple Salud tu fecha de nacimiento, sexo, grupo sanguíneo, altura, peso y composición corporal, y tu sueño y pasos si los incluyes. Solo lectura: nunca escribe en Salud. Lo que Salud no tenga aparece como \"No disponible\"."))
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>, hasData: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                if !hasData {
                    Text(String(localized: "reports.medical.noData", defaultValue: "Sin datos en este período"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!hasData)
    }

    private func generate() {
        nameFocused = false
        viewModel.start()
    }

    // MARK: Progreso y vista previa

    private func progress(done: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: total > 0 ? Double(done) : nil, total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)
            Text(String(localized: "reports.medical.generating", defaultValue: "Generando el PDF…"))
                .font(.headline)
            if total > 0 {
                Text(String(localized: "reports.medical.progress", defaultValue: "Página \(done) de \(total)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func preview(_ url: URL) -> some View {
        MedicalPDFPreview(url: url)
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                shareLink(url, prominent: true)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .accessibilityLabel(String(localized: "reports.medical.preview", defaultValue: "Vista previa del PDF"))
    }

    @ViewBuilder
    private func shareLink(_ url: URL, prominent: Bool = false) -> some View {
        let link = ShareLink(
            item: url,
            preview: SharePreview(url.lastPathComponent, image: Image(systemName: "doc.richtext"))
        ) {
            Label(String(localized: "reports.medical.share", defaultValue: "Compartir"), systemImage: "square.and.arrow.up")
                .frame(maxWidth: prominent ? .infinity : nil)
        }
        if prominent {
            link.buttonStyle(.borderedProminent)
        } else {
            link
        }
    }
}
