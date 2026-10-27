import Foundation
import LingoCore
import Observation

/// Dónde se escribe y de dónde se importa (contrato §3.2).
enum ArchiveDestination: Sendable, Equatable {
    /// Carpeta elegida por Juampa con el selector del sistema (bookmark con alcance de seguridad).
    case userFolder(URL)
    /// Fallback explícito al contenedor iCloud de la app, solo si nunca se eligió carpeta. La UI lo dice.
    case appICloudContainer(URL)
    /// Sin destino utilizable (bookmark caducado, iCloud apagado…): la UI pide elegir carpeta.
    case unavailable(String)

    var url: URL? {
        switch self {
        case .userFolder(let u), .appICloudContainer(let u): u
        case .unavailable: nil
        }
    }

    var isFallback: Bool { if case .appICloudContainer = self { true } else { false } }
}

/// Un paquete `.lingoscan` de la carpeta destino y lo que el sistema dice de su subida a iCloud.
struct ArchivePackageStatus: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let url: URL
    let producerTag: String
    let createdAt: UTCInstant
    /// Paquete escrito por esta app (`producer_tag` `lingoscan`).
    let isOwn: Bool
    let upload: ArchiveUploadState
}

/// Exportación, importación y estado de la copia portable `.lingoscan` (T-10, `CONTRATO_V1.md`).
///
/// - Escribe en la carpeta elegida (bookmark) o, si nunca se eligió, en el contenedor iCloud propio.
/// - Muestra el estado de iCloud por paquete a partir de lo que informa el sistema; no presume subida.
/// - Importa paquetes de cualquier productor con las reglas de unión de §8, en una transacción por paquete.
@MainActor
@Observable
final class ArchiveService {
    private(set) var destination: ArchiveDestination = .unavailable("Sin resolver")
    private(set) var packages: [ArchivePackageStatus] = []
    private(set) var isWorking = false
    private(set) var lastExport: ArchiveExportResult?
    private(set) var lastImport: [PackageImportOutcome] = []
    private(set) var lastError: String?

    private let store: SQLiteStore
    private let databasePath: String
    private let bookmarks: any FolderBookmarkStoring
    private let fallbackContainer: @Sendable () async -> URL?
    private let producer: ArchiveProducerInfo
    private let healthState: @Sendable () -> ArchiveHealthState
    private let now: @Sendable () -> Date
    private let minimumInterval: TimeInterval

    init(
        store: SQLiteStore,
        databasePath: String,
        bookmarks: any FolderBookmarkStoring = UserDefaultsFolderBookmarkStore(),
        fallbackContainer: @escaping @Sendable () async -> URL? = ArchiveService.iCloudContainerDocuments,
        producer: ArchiveProducerInfo = ArchiveService.currentProducer(),
        healthState: @escaping @Sendable () -> ArchiveHealthState = { .lingoScanActive },
        minimumInterval: TimeInterval = 20 * 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.databasePath = databasePath
        self.bookmarks = bookmarks
        self.fallbackContainer = fallbackContainer
        self.producer = producer
        self.healthState = healthState
        self.minimumInterval = minimumInterval
        self.now = now
    }

    // MARK: Destino

    /// Resuelve el destino sin escribir nada. Una carpeta elegida cuyo bookmark ya no resuelve **no** cae al
    /// contenedor propio en silencio: queda `unavailable` y la UI pide elegir de nuevo.
    func resolveDestination() async -> ArchiveDestination {
        if let data = bookmarks.load() {
            do {
                let resolved = try FolderBookmark.resolve(data)
                if let fresh = resolved.refreshedData { bookmarks.save(fresh) }
                return .userFolder(resolved.url)
            } catch {
                return .unavailable("La carpeta elegida ya no es accesible. Elígela de nuevo.")
            }
        }
        if let container = await fallbackContainer() { return .appICloudContainer(container) }
        return .unavailable("iCloud Drive no está disponible y no hay carpeta elegida.")
    }

    /// Guarda la carpeta que devolvió el selector del sistema.
    func chooseFolder(_ url: URL) async {
        do {
            let data = try SecurityScopedAccess.run(url) { try FolderBookmark.make(from: url) }
            bookmarks.save(data)
            lastError = nil
        } catch {
            lastError = "No se pudo recordar la carpeta: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Vuelve al contenedor propio de iCloud (olvida la carpeta elegida).
    func forgetFolder() async {
        bookmarks.save(nil)
        await refresh()
    }

    /// Resuelve el destino y lista sus paquetes con el estado de iCloud de cada uno.
    func refresh() async {
        destination = await resolveDestination()
        guard let folder = destination.url else {
            packages = []
            return
        }
        packages = await Self.listPackages(in: folder)
    }

    /// Borra las `*.lingoscan.partial` abandonadas de este productor (§3.1). Llamar al arrancar.
    func removeAbandonedPartials() async {
        let destination = await resolveDestination()
        guard let folder = destination.url else { return }
        let tag = producer.producerTag
        let removed = (try? await SecurityScopedAccess.run(folder) {
            try await Task.detached { try LingoScanArchiveWriter.removeAbandonedPartials(in: folder, producerTag: tag) }.value
        }) ?? []
        if !removed.isEmpty {
            try? await store.logEvent(.info, category: "archive", "carpetas .partial abandonadas borradas: \(removed.count)")
        }
    }

    // MARK: Exportar

    /// Exportación manual (o por fin de sensor). No hace nada si ya hay una operación en curso.
    @discardableResult
    func exportNow() async -> ArchiveExportResult? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        destination = await resolveDestination()
        guard let folder = destination.url else {
            lastError = Self.message(for: destination)
            return nil
        }
        let exporter = ArchiveExporter(
            store: store, databasePath: databasePath, writer: LingoScanArchiveWriter(producer: producer),
            health: healthState, now: now)
        do {
            let result = try await SecurityScopedAccess.run(folder) { try await exporter.export(to: folder) }
            lastExport = result
            lastError = result.verified ? nil : "El paquete se escribió pero no pasó la validación: \(result.verificationFailure ?? "motivo desconocido")"
            try? await store.logEvent(
                .info, category: "archive",
                "exportado \(public: String(result.archiveID.prefix(8))): \(result.manifest.counts.readings) lecturas, verificado \(result.verified), retención borró \(result.removedByRetention.count)")
            packages = await Self.listPackages(in: folder)
            return result
        } catch {
            lastError = "No se pudo exportar: \(error.localizedDescription)"
            try? await store.logEvent(.error, category: "archive", "exportación fallida: \(public: String(describing: type(of: error)))")
            return nil
        }
    }

    /// Para la tarea diaria: exporta solo si el último paquete propio tiene más de `minimumInterval`.
    /// Devuelve `true` si ya había una copia reciente o la exportación terminó bien.
    @discardableResult
    func exportIfDue() async -> Bool {
        await refresh()
        guard destination.url != nil else { return false }
        let current = UTCInstant(now())
        if let last = packages.filter(\.isOwn).map(\.createdAt).max(),
           Double(current.epochSeconds - last.epochSeconds) < minimumInterval { return true }
        return await exportNow()?.verified ?? false
    }

    // MARK: Importar

    /// Importa un paquete `.lingoscan` o todos los de una carpeta (lo que devuelva el selector). Cada paquete en su
    /// propia transacción; uno inválido no impide importar los demás. Un `archive_id` ya conocido se omite.
    @discardableResult
    func importPackages(from url: URL) async -> [PackageImportOutcome] {
        guard !isWorking else { return [] }
        isWorking = true
        defer { isWorking = false }
        let importer = ArchiveImporter(databasePath: databasePath, now: now)
        let outcomes: [PackageImportOutcome] = await SecurityScopedAccess.run(url) {
            await Task.detached {
                let isPackage = url.pathExtension == "lingoscan"
                if isPackage {
                    _ = await ICloudItemStatus.ensureDownloaded(package: url)
                    return [importer.importOutcome(at: url)]
                }
                let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
                    .filter { $0.hasSuffix(ArchivePackageName.suffix) && !ArchivePackageName.isPartial($0) }
                for n in names { _ = await ICloudItemStatus.ensureDownloaded(package: url.appending(path: n, directoryHint: .isDirectory)) }
                return importer.importAll(in: url)
            }.value
        }
        lastImport = outcomes
        let imported = outcomes.reduce(0) { if case .imported = $1 { $0 + 1 } else { $0 } }
        let rejected = outcomes.reduce(0) { if case .rejected = $1 { $0 + 1 } else { $0 } }
        lastError = rejected > 0 ? "\(rejected) paquete(s) rechazado(s); la base no cambió con ellos." : nil
        try? await store.logEvent(.info, category: "archive", "importación: \(imported) paquetes importados, \(rejected) rechazados de \(outcomes.count)")
        return outcomes
    }

    /// Importa los paquetes que haya en el destino actual (p. ej. los de la otra app en la misma carpeta).
    @discardableResult
    func importFromDestination() async -> [PackageImportOutcome] {
        destination = await resolveDestination()
        guard let folder = destination.url else {
            lastError = Self.message(for: destination)
            return []
        }
        return await importPackages(from: folder)
    }

    // MARK: Utilidades

    private static func message(for destination: ArchiveDestination) -> String {
        if case .unavailable(let reason) = destination { return reason }
        return "Sin destino."
    }

    nonisolated static func listPackages(in folder: URL) async -> [ArchivePackageStatus] {
        await Task.detached {
            SecurityScopedAccess.run(folder) {
                let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                return items.compactMap { url -> ArchivePackageStatus? in
                    guard let name = ArchivePackageName(parsing: url.lastPathComponent) else { return nil }
                    return ArchivePackageStatus(
                        name: url.lastPathComponent, url: url, producerTag: name.producerTag, createdAt: name.createdAt,
                        isOwn: name.producerTag == "lingoscan", upload: ICloudItemStatus.state(ofPackage: url))
                }.sorted { ($0.createdAt, $0.name) > ($1.createdAt, $1.name) }
            }
        }.value
    }

    /// `Documents` del contenedor iCloud propio (visible en Archivos → LingoScan). La primera llamada puede tardar:
    /// por eso corre fuera del hilo principal.
    nonisolated static func iCloudContainerDocuments() async -> URL? {
        await Task.detached {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.otalvaro.lingoscan") else { return nil }
            let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
    }

    /// `manifest.producer` y `manifest.device` de esta instalación.
    nonisolated static func currentProducer(bundle: Bundle = .main) -> ArchiveProducerInfo {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return .lingoScan(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            deviceModel: model.isEmpty ? "unknown" : model,
            osVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    }
}
