import Foundation

/// Quién produce el paquete (`manifest.producer` y `manifest.device`).
public struct ArchiveProducerInfo: Sendable, Hashable {
    public var appID: String
    public var producerTag: String
    public var appName: String
    public var appVersion: String
    public var build: String
    public var decoder: DecoderInfo
    public var deviceModel: String
    public var osVersion: String

    public init(appID: String, producerTag: String, appName: String, appVersion: String, build: String,
                decoder: DecoderInfo, deviceModel: String, osVersion: String) {
        self.appID = appID
        self.producerTag = producerTag
        self.appName = appName
        self.appVersion = appVersion
        self.build = build
        self.decoder = decoder
        self.deviceModel = deviceModel
        self.osVersion = osVersion
    }

    /// `com.otalvaro.lingoscan`, `producer_tag` `lingoscan`.
    public static func lingoScan(appVersion: String, build: String, deviceModel: String, osVersion: String) -> ArchiveProducerInfo {
        ArchiveProducerInfo(appID: "com.otalvaro.lingoscan", producerTag: "lingoscan", appName: "LingoScan",
                            appVersion: appVersion, build: build, decoder: .lingoScan,
                            deviceModel: deviceModel, osVersion: osVersion)
    }
}

/// Estado de Health que el productor declara en `manifest.health` (contrato §4 y §7).
/// Lo fija quien manda en Health (T-09, T-19); el archivo solo lo transporta.
public struct ArchiveHealthState: Sendable, Hashable {
    public var writerAppID: String?
    /// Instante de pausa si la escritora saliente se puso en pausa para transferir el rol (§7.4).
    public var handoverAt: UTCInstant?

    public init(writerAppID: String?, handoverAt: UTCInstant? = nil) {
        self.writerAppID = writerAppID
        self.handoverAt = handoverAt
    }

    public static let lingoScanActive = ArchiveHealthState(writerAppID: "com.otalvaro.lingoscan")
}

/// Puntos del protocolo §3.1 en los que una prueba puede cortar la exportación.
public enum ArchiveExportStep: Sendable, Hashable {
    /// Paso 1 hecho: existe la carpeta `.partial`.
    case partialCreated
    /// Paso 2 hecho: todos los archivos salvo `manifest.json`.
    case dataFilesWritten
    /// Paso 4 hecho: `manifest.json` escrito, aún sin renombrar.
    case manifestWritten
}

/// Muerte simulada del proceso: el escritor la propaga sin limpiar, como si la app hubiera muerto.
public struct ArchiveSimulatedInterruption: Error, Sendable, Hashable {
    public let step: ArchiveExportStep
    public init(step: ArchiveExportStep) { self.step = step }
}

/// Escribe un paquete `.lingoscan` según el protocolo del contrato §3.1:
/// carpeta `.partial` → archivos → hashes → `manifest.json` al final con `snapshot.complete = true` → renombrado.
public struct LingoScanArchiveWriter: Sendable {
    public typealias Interruption = @Sendable (ArchiveExportStep) throws -> Void

    public static let readmeText = """
    # Paquete LingoScan

    Historial de glucosa, diario y registro de escrituras en Apple Salud exportado por LingoScan.
    El formato es el contrato `LingoScan_Shared/CONTRATO_V1.md` (esquemas en `LingoScan_Shared/schemas/`).
    `manifest.json` lista el SHA-256 de cada archivo; si falta o `snapshot.complete` no es `true`, el paquete no es un respaldo.
    `readings.csv` es solo para humanos y nunca se importa.

    """

    public let producer: ArchiveProducerInfo
    public let policy: ArchiveManifest.Policy
    private let interruption: Interruption?

    public init(producer: ArchiveProducerInfo,
                policy: ArchiveManifest.Policy = .init(eligibilityPolicyID: LingoScanV1Policy.policyID,
                                                       eligibilityPolicyVersion: LingoScanV1Policy.policyVersion),
                interruption: Interruption? = nil) {
        self.producer = producer
        self.policy = policy
        self.interruption = interruption
    }

    /// Nombre de la carpeta final que producirá `write` para este `archiveID` y esta fecha.
    public func folderName(archiveID: String, createdAt: UTCInstant) -> String {
        ArchivePackageName(producerTag: producer.producerTag, createdAt: createdAt, archiveID: archiveID).folderName
    }

    @discardableResult
    public func write(_ content: ArchiveContent, health: ArchiveHealthState = .lingoScanActive,
                      archiveID: String = UUID().uuidString.lowercased(), createdAt: UTCInstant,
                      into directory: URL) throws -> WrittenArchive {
        let fm = FileManager.default
        let name = ArchivePackageName(producerTag: producer.producerTag, createdAt: createdAt, archiveID: archiveID)
        let partial = directory.appending(path: name.partialFolderName, directoryHint: .isDirectory)
        let final = directory.appending(path: name.folderName, directoryHint: .isDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Paso 1.
        try fm.createDirectory(at: partial, withIntermediateDirectories: false)
        do {
            try interrupt(.partialCreated)

            // Paso 2: todos los archivos salvo el manifest.
            let content = Self.sorted(content)
            var written: [(name: String, data: Data, records: Int)] = []
            func put(_ file: String, _ data: Data, records: Int) throws {
                try data.write(to: partial.appending(path: file, directoryHint: .notDirectory))
                written.append((file, data, records))
            }
            try put("sessions.json", try Self.sessionsFile(content.sessions), records: content.sessions.count)
            try put("readings.ndjson", try NDJSON.encode(content.readings.map(JSONValue.encoding)), records: content.readings.count)
            try put("events.ndjson", try NDJSON.encode(try content.events.map(Self.eventJSON)), records: content.events.count)
            try put("health_export_ledger.ndjson", try NDJSON.encode(content.ledger.map(JSONValue.encoding)), records: content.ledger.count)
            if !content.conflicts.isEmpty {
                try put("conflicts.ndjson", try NDJSON.encode(content.conflicts.map(JSONValue.encoding)), records: content.conflicts.count)
            }
            try put("readings.csv", CSVWriter.file(for: content.readings), records: content.readings.count)
            try Data(Self.readmeText.utf8).write(to: partial.appending(path: "README.md", directoryHint: .notDirectory))
            try interrupt(.dataFilesWritten)

            // Paso 3 y 4: hashes y manifest al final.
            let manifest = makeManifest(content: content, health: health, archiveID: archiveID, createdAt: createdAt,
                                        files: written.map {
                                            ArchiveManifest.FileEntry(name: $0.name, bytes: $0.data.count,
                                                                      sha256: ArchiveHashing.sha256Hex($0.data), records: $0.records)
                                        })
            let manifestData = try NDJSON.makeEncoder(pretty: true).encode(manifest) + Data("\n".utf8)
            try manifestData.write(to: partial.appending(path: ArchiveManifest.fileName, directoryHint: .notDirectory))
            try interrupt(.manifestWritten)

            // Paso 5: renombrado.
            try fm.moveItem(at: partial, to: final)
            return WrittenArchive(url: final, manifest: manifest, manifestSHA256: ArchiveHashing.sha256Hex(manifestData))
        } catch let stop as ArchiveSimulatedInterruption {
            throw stop  // la app "murió": la carpeta .partial queda y se borra en el siguiente arranque
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
    }

    private func interrupt(_ step: ArchiveExportStep) throws {
        if let interruption {
            do { try interruption(step) } catch is ArchiveSimulatedInterruption { throw ArchiveSimulatedInterruption(step: step) }
        }
    }

    /// Borra las carpetas `*.lingoscan.partial` abandonadas **de este productor** (contrato §3.1: se borran en el
    /// siguiente arranque). Nunca toca las de otro `producer_tag`: pueden estar escribiéndose ahora mismo.
    @discardableResult
    public static func removeAbandonedPartials(in directory: URL, producerTag: String) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let prefix = "LingoScan-\(producerTag)-"
        var removed: [String] = []
        for item in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let n = item.lastPathComponent
            guard ArchivePackageName.isPartial(n), n.hasPrefix(prefix) else { continue }
            try fm.removeItem(at: item)
            removed.append(n)
        }
        return removed.sorted()
    }

    // MARK: - Piezas

    func makeManifest(content: ArchiveContent, health: ArchiveHealthState, archiveID: String, createdAt: UTCInstant,
                      files: [ArchiveManifest.FileEntry]) -> ArchiveManifest {
        let everything = content.sessions.map(\.synthetic) + content.readings.map(\.synthetic) + content.events.map(\.event.synthetic)
        let allSynthetic = !everything.isEmpty && everything.allSatisfy { $0 }
        return ArchiveManifest(
            archiveID: archiveID, createdAt: createdAt,
            producer: .init(appID: producer.appID, producerTag: producer.producerTag, appName: producer.appName,
                            appVersion: producer.appVersion, build: producer.build,
                            decoderID: producer.decoder.id, decoderVersion: producer.decoder.version),
            device: .init(model: producer.deviceModel, osVersion: producer.osVersion),
            snapshot: .init(kind: .full, from: nil, to: createdAt, complete: true),
            policy: policy, synthetic: allSynthetic,
            health: ArchiveHealthDerivation.healthBlock(content: content, writerAppID: health.writerAppID, handoverAt: health.handoverAt),
            counts: .init(sessions: content.sessions.count, readings: content.readings.count, events: content.events.count,
                          ledgerEntries: content.ledger.count, conflicts: content.conflicts.count),
            files: files)
    }

    /// Orden recomendado (§2): sesión y `life_count` ascendente. El ledger y los conflictos conservan el orden de
    /// inserción (son append-only).
    static func sorted(_ c: ArchiveContent) -> ArchiveContent {
        var c = c
        c.sessions.sort { ($0.activationTimeEpochS, $0.sessionID) < ($1.activationTimeEpochS, $1.sessionID) }
        c.readings.sort { ($0.sessionID, $0.analyte.rawValue, $0.lifeCount) < ($1.sessionID, $1.analyte.rawValue, $1.lifeCount) }
        c.events.sort { $0.event.eventID < $1.event.eventID }
        return c
    }

    static func sessionsFile(_ sessions: [SensorSessionRecord]) throws -> Data {
        let value = JSONValue.object(["sessions": .array(try sessions.map(JSONValue.encoding))])
        return try NDJSON.makeEncoder(pretty: true).encode(value) + Data("\n".utf8)
    }

    /// Evento con `edit_ancestors` cuando la cadena completa es conocida; sin ella se omite la clave (no se
    /// inventa un ancestro, draft.4).
    static func eventJSON(_ e: ArchiveEvent) throws -> JSONValue {
        guard case .object(var object) = try JSONValue.encoding(e.event) else { return .null }
        if let ancestors = e.ancestors { object["edit_ancestors"] = try JSONValue.encoding(ancestors) }
        return .object(object)
    }
}
