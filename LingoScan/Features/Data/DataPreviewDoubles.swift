import Foundation
import LingoCore

/// Dobles inertes para la previsualización (`-previewSensorState`, `#Preview`) y las pruebas.
/// No tocan Health, iCloud ni la base: la pantalla muestra estados neutros, nunca datos inventados.
@MainActor
final class PreviewArchiveManager: ArchiveManaging {
    var destination: ArchiveDestination = .unavailable("Vista previa: sin carpeta de archivo.")
    var packages: [ArchivePackageStatus] = []
    var isWorking = false
    var lastError: String?

    func refresh() async {}
    func chooseFolder(_ url: URL) async {}
    func forgetFolder() async {}
    func exportNow() async -> ArchiveExportSummary? { nil }
    func importPackages(from url: URL) async -> [ArchiveImportLine] { [] }
}

struct PreviewHealthController: HealthControlling {
    var current = HealthSnapshot()

    func snapshot() async -> HealthSnapshot { current }
    func requestAuthorization() async -> HealthSnapshot { current }
    func fillGaps() async -> HealthFillResult { HealthFillResult(summary: HealthDrainSummary(), snapshot: current) }
}

struct EmptyEventLog: EventLogReading {
    func recentLogEvents(limit: Int) async throws -> [EventLogEntry] { [] }
}
