import Foundation
import LingoCore
import Observation

/// Estado de la hoja "Reporte para el médico" (T-34): editando → generando → listo (URL del PDF) o error.
///
/// Apple Salud se lee solo al pulsar "Generar PDF" (nunca antes, nunca para escribir). Lo que Salud no devuelva queda
/// como "No disponible en Apple Salud" y el PDF se genera igual. El archivo vive en el directorio temporal y se borra al
/// cerrar la hoja (`cleanUp`).
@MainActor
@Observable
final class MedicalReportViewModel {
    enum Phase: Equatable {
        case editing
        /// Páginas dibujadas y total (0 mientras se lee Salud y se arma el documento).
        case generating(done: Int, total: Int)
        case ready(URL)
        case failed
    }

    /// Prefijo de las carpetas temporales de PDF; las de más de un día se borran al generar.
    static let folderPrefix = "Lingclose-medical-"

    private(set) var phase: Phase = .editing
    var options: MedicalReportOptions
    /// Nombre del paciente; al editarlo se guarda en el dispositivo (`MedicalReportNameStore`).
    var name: String {
        didSet { nameStore.name = name }
    }

    let content: ReportContent
    /// Qué secciones tienen datos en el período (las que no, quedan apagadas y deshabilitadas en la hoja).
    let hasMeals: Bool
    let hasExercise: Bool
    let hasNotes: Bool

    @ObservationIgnored private let isSynthetic: Bool
    @ObservationIgnored private let health: ReportAnalysisHealthSources
    @ObservationIgnored private let nutrition: any MealNutritionStore
    @ObservationIgnored private let nameStore: MedicalReportNameStore
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let unit: MedicalGlucoseUnit
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var fileFolder: URL?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(content: ReportContent, isSynthetic: Bool, health: ReportAnalysisHealthSources,
         nutrition: any MealNutritionStore, nameStore: MedicalReportNameStore = MedicalReportNameStore(),
         clock: @escaping @Sendable () -> Date = { .now }, locale: Locale = .current,
         unit: MedicalGlucoseUnit = .mgdl, directory: URL = FileManager.default.temporaryDirectory) {
        self.content = content
        self.isSynthetic = isSynthetic
        self.health = health
        self.nutrition = nutrition
        self.nameStore = nameStore
        self.clock = clock
        self.locale = locale
        self.unit = unit
        self.directory = directory
        name = nameStore.name
        let period = content.bundle.period
        hasMeals = !content.bundle.meals.meals.isEmpty
        hasExercise = !content.bundle.exercise.sessions.isEmpty
        hasNotes = content.events.contains {
            ($0.kind == .note || $0.kind == .sensorNote) && !$0.deleted && period.contains($0.at)
                && !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var options = MedicalReportOptions.all
        options.meals = hasMeals
        options.exercise = hasExercise
        options.notes = hasNotes
        self.options = options
    }

    var isGenerating: Bool {
        if case .generating = phase { return true }
        return false
    }

    var periodText: String {
        let bundle = content.bundle
        let range = ReportFormat.range(bundle.period)
        return String(localized: "reports.period.caption",
                      defaultValue: "\(range) · \(bundle.summary.daysWithData) de \(bundle.dayCount) días con datos")
    }

    // MARK: Acciones

    /// Lanza `generate()` en una tarea que `cancel()` puede detener (al cerrar la hoja).
    func start() {
        task?.cancel()
        task = Task { await generate() }
    }

    /// Detiene la generación en curso, si la hay, y borra el PDF temporal.
    func cancel() {
        task?.cancel()
        task = nil
        cleanUp()
    }

    /// Lee Apple Salud, arma el documento, lo dibuja y deja el PDF en un archivo temporal.
    func generate() async {
        guard !isGenerating else { return }
        phase = .generating(done: 0, total: 0)
        cleanUp()
        Self.purgeStaleFolders(in: directory)
        do {
            let document = await buildDocument()
            guard !Task.isCancelled else { phase = .editing; return }
            let data = try await MedicalPDFRenderer.render(document) { [weak self] done, total in
                self?.phase = .generating(done: done, total: total)
            }
            guard !Task.isCancelled else { phase = .editing; return }
            phase = .ready(try write(data, named: document.fileName))
        } catch {
            phase = .failed
        }
    }

    /// Vuelve a la edición (desde la vista previa o tras un error); el archivo anterior se borra.
    func backToEditing() {
        cleanUp()
        phase = .editing
    }

    /// Borra el PDF temporal. Se llama al cerrar la hoja.
    func cleanUp() {
        if let fileFolder { try? FileManager.default.removeItem(at: fileFolder) }
        fileFolder = nil
    }

    // MARK: Interno

    private func buildDocument() async -> MedicalReportDocument {
        let bundle = content.bundle
        let period = bundle.period
        let timeZone = period.timeZone
        let from = period.start.date, to = period.end.date
        let options = options

        // Salud: solo lectura, al pulsar "Generar PDF". Perfil y composición siempre (datos del paciente).
        await health.bodyComposition.requestAuthorization()
        let profile = (try? await health.medicalProfile.readProfile()) ?? .empty
        let body = await health.bodyComposition.bodyComposition(from: from, to: to, timeZone: timeZone)
        let series = options.bodyComposition ? await health.bodyComposition.bodyMeasurementSeries(from: from, to: to) : .empty
        var nights: [SleepNight] = []
        var steps: [DailySteps] = []
        if options.sleepActivity {
            await health.sleepActivity.requestAuthorization()
            nights = await health.sleepActivity.sleepNights(from: from.addingTimeInterval(-12 * 3_600), to: to, timeZone: timeZone)
            steps = await health.sleepActivity.dailySteps(from: from, to: to, timeZone: timeZone)
        }
        var records: [String: MealNutritionRecord] = [:]
        if options.meals {
            let times = Set(bundle.meals.meals.map(\.at))
            for event in content.events where event.kind == .meal && !event.deleted && times.contains(event.at) {
                if let record = try? await nutrition.mealNutrition(eventID: event.eventID) {
                    records[event.eventID] = record
                }
            }
        }
        let input = MedicalReportInput(
            bundle: bundle, events: content.events, nutrition: records, profile: profile, body: body, bodySeries: series,
            sleep: nights, steps: steps, options: options, patientName: name, isSynthetic: isSynthetic,
            generatedAt: clock(), unit: unit, locale: locale)
        return await Task.detached(priority: .userInitiated) { MedicalReportBuilder.build(input) }.value
    }

    private func write(_ data: Data, named fileName: String) throws -> URL {
        let folder = directory.appendingPathComponent(Self.folderPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        fileFolder = folder
        return url
    }

    /// Carpetas de PDF de sesiones anteriores que no se limpiaron (cierre brusco): se borran si pasó más de un día.
    static func purgeStaleFolders(in directory: URL, now: Date = .now) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in items where item.lastPathComponent.hasPrefix(folderPrefix) {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > 86_400 { try? manager.removeItem(at: item) }
        }
    }
}
