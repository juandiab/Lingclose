import Foundation

/// Resultado de una exportación completa.
public struct ArchiveExportResult: Sendable {
    public let url: URL
    public let archiveID: String
    public let manifest: ArchiveManifest
    /// El paquete recién renombrado pasó la validación completa del lector (hashes, esquemas, conteos).
    public let verified: Bool
    /// Motivo si `verified == false`. El paquete se conserva igualmente: es el único respaldo que hay.
    public let verificationFailure: String?
    /// Paquetes propios que borró la retención de §3.3.
    public let removedByRetention: [String]
    /// `*.partial` propios abandonados que se borraron antes de exportar.
    public let removedPartials: [String]
}

/// Exporta el estado completo de la base como un paquete `.lingoscan` (contrato §3) y lo registra en `archives`
/// solo después del renombrado atómico (paso 6): un corte durante la exportación no deja nada registrado.
public struct ArchiveExporter: Sendable {
    public let store: SQLiteStore
    public let databasePath: String
    public let writer: LingoScanArchiveWriter
    private let health: @Sendable () -> ArchiveHealthState
    private let now: @Sendable () -> Date

    public init(store: SQLiteStore, databasePath: String, writer: LingoScanArchiveWriter,
                health: @escaping @Sendable () -> ArchiveHealthState = { .lingoScanActive },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.databasePath = databasePath
        self.writer = writer
        self.health = health
        self.now = now
    }

    /// Exporta a `directory`. Antes borra los `*.partial` abandonados de este productor (§3.1) y después aplica la
    /// retención (§3.3) si la validación del paquete nuevo fue correcta.
    public func export(to directory: URL) async throws -> ArchiveExportResult {
        let tag = writer.producer.producerTag
        let removedPartials = try LingoScanArchiveWriter.removeAbandonedPartials(in: directory, producerTag: tag)
        let createdAt = UTCInstant(now())
        let healthState = health()
        let writer = writer
        let path = databasePath
        let written = try ArchiveExporter.writeSynchronously(writer: writer, databasePath: path, health: healthState,
                                                              createdAt: createdAt, directory: directory)

        // Paso 6: registro, solo con el paquete ya renombrado.
        var verified = false
        var failure: String?
        do {
            _ = try LingoScanArchiveReader().read(at: written.url)
            verified = true
        } catch {
            failure = (error as? ArchiveValidationError)?.localizedDescription ?? "\(error)"
        }
        try await store.recordArchive(ArchiveRecord(
            archiveID: written.manifest.archiveID, createdAt: written.manifest.createdAt, path: written.url.path,
            readings: written.manifest.counts.readings, manifestSHA256: written.manifestSHA256, verified: verified))
        var removed: [String] = []
        if verified { removed = try ArchiveRetention.apply(in: directory, producerTag: tag) }
        return ArchiveExportResult(url: written.url, archiveID: written.manifest.archiveID, manifest: written.manifest,
                                   verified: verified, verificationFailure: failure, removedByRetention: removed,
                                   removedPartials: removedPartials)
    }

    private static func writeSynchronously(writer: LingoScanArchiveWriter, databasePath: String, health: ArchiveHealthState,
                                           createdAt: UTCInstant, directory: URL) throws -> WrittenArchive {
        let content = try ArchiveSnapshotReader(databasePath: databasePath).snapshot()
        return try writer.write(content, health: health, createdAt: createdAt, into: directory)
    }
}
