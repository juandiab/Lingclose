import Foundation
import PDFKit
import Testing
@testable import LingoScan

/// T-34: la hoja lee Apple Salud solo al generar, deja un PDF temporal y lo borra al cerrar.
@MainActor
struct MedicalReportViewModelTests {
    /// Cuenta cuántas veces se pide algo a Salud.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func hit() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    struct CountingProfile: HealthProfileReading {
        let counter: Counter
        func readProfile() async throws -> HealthProfile {
            counter.hit()
            return PreviewHealthProfileReader.medicalPreview.profile
        }
    }

    struct DeniedProfile: HealthProfileReading {
        func readProfile() async throws -> HealthProfile { throw HealthProfileError.authorizationFailed("test") }
    }

    private func content() -> ReportContent {
        let (bundle, events) = MedicalReportFixtures.bundleWithEvents()
        return ReportContent(preset: .days14, bundle: bundle, events: events)
    }

    private func viewModel(health: ReportAnalysisHealthSources, directory: URL, defaults: UserDefaults) -> MedicalReportViewModel {
        MedicalReportViewModel(
            content: content(), isSynthetic: true, health: health, nutrition: PreviewMealNutritionStore(),
            nameStore: MedicalReportNameStore(defaults: defaults), clock: { Date(timeIntervalSince1970: 1_800_000_000) },
            locale: MedicalReportFixtures.locale, directory: directory)
    }

    private func scratch() throws -> (URL, UserDefaults, () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("t34-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "t34-vm-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (directory, defaults, {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        })
    }

    @Test func doesNotTouchHealthUntilGenerate() async throws {
        let (directory, defaults, cleanup) = try scratch()
        defer { cleanup() }
        let counter = Counter()
        let health = ReportAnalysisHealthSources(
            sleepActivity: PreviewSleepActivityReader(), profile: PreviewHealthProfileReader(),
            bodyComposition: PreviewBodyCompositionReader(), medicalProfile: CountingProfile(counter: counter))
        let model = viewModel(health: health, directory: directory, defaults: defaults)
        #expect(model.phase == .editing)
        #expect(counter.count == 0)
        await model.generate()
        #expect(counter.count == 1)
    }

    @Test func generateLeavesATemporaryPDFAndCleanUpRemovesIt() async throws {
        let (directory, defaults, cleanup) = try scratch()
        defer { cleanup() }
        let model = viewModel(health: .preview, directory: directory, defaults: defaults)
        model.name = "Paciente Prueba Zeta"
        await model.generate()
        guard case .ready(let url) = model.phase else { Issue.record("fase: \(model.phase)"); return }
        #expect(url.path.hasPrefix(directory.path))
        #expect(url.lastPathComponent.hasPrefix("Lingclose-reporte-") && url.pathExtension == "pdf")
        #expect(!url.lastPathComponent.contains("Zeta"))
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount > 1)
        #expect(try #require(pdf.string).contains("Paciente Prueba Zeta"))
        // El nombre se guardó en el dispositivo al escribirlo.
        #expect(MedicalReportNameStore(defaults: defaults).name == "Paciente Prueba Zeta")
        model.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test func aDeniedProfileStillGeneratesWithUnavailableRows() async throws {
        let (directory, defaults, cleanup) = try scratch()
        defer { cleanup() }
        let health = ReportAnalysisHealthSources(
            sleepActivity: PreviewSleepActivityReader(nights: [], steps: []), profile: PreviewHealthProfileReader(),
            bodyComposition: PreviewBodyCompositionReader(.empty), medicalProfile: DeniedProfile())
        let model = viewModel(health: health, directory: directory, defaults: defaults)
        await model.generate()
        guard case .ready(let url) = model.phase else { Issue.record("fase: \(model.phase)"); return }
        let text = try #require(PDFDocument(url: url)?.string)
        #expect(text.contains(MedicalReportStrings.unavailable))
        model.cleanUp()
    }

    @Test func sectionsWithoutDataStartSwitchedOff() throws {
        let (directory, defaults, cleanup) = try scratch()
        defer { cleanup() }
        let (bundle, _) = MedicalReportFixtures.bundleWithEvents(withDiary: false)
        let model = MedicalReportViewModel(
            content: ReportContent(preset: .days14, bundle: bundle, events: []), isSynthetic: true, health: .preview,
            nutrition: PreviewMealNutritionStore(), nameStore: MedicalReportNameStore(defaults: defaults), directory: directory)
        #expect(!model.hasMeals && !model.options.meals)
        #expect(!model.hasExercise && !model.options.exercise)
        #expect(!model.hasNotes && !model.options.notes)
        #expect(model.options.sleepActivity && model.options.bodyComposition)
    }

    @Test func nameIsPrefilledFromTheStoreAndSavedOnEdit() throws {
        let (directory, defaults, cleanup) = try scratch()
        defer { cleanup() }
        MedicalReportNameStore(defaults: defaults).name = "Marta"
        let model = viewModel(health: .preview, directory: directory, defaults: defaults)
        #expect(model.name == "Marta")
        model.name = "  Marta   Gil "
        #expect(MedicalReportNameStore(defaults: defaults).name == "Marta Gil")
    }

    @Test func staleTemporaryFoldersArePurged() throws {
        let (directory, _, cleanup) = try scratch()
        defer { cleanup() }
        let old = directory.appendingPathComponent(MedicalReportViewModel.folderPrefix + "old", isDirectory: true)
        let recent = directory.appendingPathComponent(MedicalReportViewModel.folderPrefix + "recent", isDirectory: true)
        for folder in [old, recent] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: old.path)
        MedicalReportViewModel.purgeStaleFolders(in: directory)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
}
