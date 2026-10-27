import Foundation

/// `manifest.json` (contrato §4). Se escribe al final del protocolo §3.1, con `snapshot.complete = true`.
public struct ArchiveManifest: Sendable, Hashable, Codable {
    public static let contractVersion = "1.0.0-draft.4"
    public static let supportedContractMajor = 1
    public static let supportedSchemaVersion = 1
    public static let fileName = "manifest.json"

    public var contractVersion: String
    public var schemaVersion: Int
    public var archiveID: String
    public var createdAt: UTCInstant
    public var producer: Producer
    public var device: Device
    public var snapshot: Snapshot
    public var policy: Policy
    public var synthetic: Bool
    public var health: Health
    public var counts: Counts
    public var files: [FileEntry]

    public struct Producer: Sendable, Hashable, Codable {
        public var appID: String
        public var producerTag: String
        public var appName: String
        public var appVersion: String
        public var build: String
        public var decoderID: String
        public var decoderVersion: String

        public init(appID: String, producerTag: String, appName: String, appVersion: String, build: String,
                    decoderID: String, decoderVersion: String) {
            self.appID = appID
            self.producerTag = producerTag
            self.appName = appName
            self.appVersion = appVersion
            self.build = build
            self.decoderID = decoderID
            self.decoderVersion = decoderVersion
        }

        enum CodingKeys: String, CodingKey {
            case appID = "app_id", producerTag = "producer_tag", appName = "app_name", appVersion = "app_version"
            case build, decoderID = "decoder_id", decoderVersion = "decoder_version"
        }
    }

    public struct Device: Sendable, Hashable, Codable {
        public var model: String
        public var osVersion: String

        public init(model: String, osVersion: String) {
            self.model = model
            self.osVersion = osVersion
        }

        enum CodingKeys: String, CodingKey { case model, osVersion = "os_version" }
    }

    public enum SnapshotKind: String, Sendable, Hashable, Codable {
        case full
        case partial
    }

    public struct Snapshot: Sendable, Hashable, Codable {
        public var kind: SnapshotKind
        public var from: UTCInstant?
        public var to: UTCInstant
        public var complete: Bool

        public init(kind: SnapshotKind, from: UTCInstant?, to: UTCInstant, complete: Bool) {
            self.kind = kind
            self.from = from
            self.to = to
            self.complete = complete
        }

        enum CodingKeys: String, CodingKey { case kind, from = "from_utc", to = "to_utc", complete }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(from, forKey: .from)
            try c.encode(to, forKey: .to)
            try c.encode(complete, forKey: .complete)
        }
    }

    public struct Policy: Sendable, Hashable, Codable {
        public var eligibilityPolicyID: String
        public var eligibilityPolicyVersion: String

        public init(eligibilityPolicyID: String, eligibilityPolicyVersion: String) {
            self.eligibilityPolicyID = eligibilityPolicyID
            self.eligibilityPolicyVersion = eligibilityPolicyVersion
        }

        enum CodingKeys: String, CodingKey {
            case eligibilityPolicyID = "eligibility_policy_id"
            case eligibilityPolicyVersion = "eligibility_policy_version"
        }
    }

    public struct Health: Sendable, Hashable, Codable {
        public var writerAppID: String?
        public var handoverAt: UTCInstant?
        public var lastConfirmedMeasuredAt: UTCInstant?
        public var pendingSubjects: Int

        public init(writerAppID: String?, handoverAt: UTCInstant?, lastConfirmedMeasuredAt: UTCInstant?,
                    pendingSubjects: Int) {
            self.writerAppID = writerAppID
            self.handoverAt = handoverAt
            self.lastConfirmedMeasuredAt = lastConfirmedMeasuredAt
            self.pendingSubjects = pendingSubjects
        }

        enum CodingKeys: String, CodingKey {
            case writerAppID = "writer_app_id"
            case handoverAt = "handover_at_utc"
            case lastConfirmedMeasuredAt = "last_confirmed_measured_at_utc"
            case pendingSubjects = "pending_subjects"
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(writerAppID, forKey: .writerAppID)
            try c.encode(handoverAt, forKey: .handoverAt)
            try c.encode(lastConfirmedMeasuredAt, forKey: .lastConfirmedMeasuredAt)
            try c.encode(pendingSubjects, forKey: .pendingSubjects)
        }
    }

    public struct Counts: Sendable, Hashable, Codable {
        public var sessions: Int
        public var readings: Int
        public var events: Int
        public var ledgerEntries: Int
        public var conflicts: Int

        public init(sessions: Int, readings: Int, events: Int, ledgerEntries: Int, conflicts: Int) {
            self.sessions = sessions
            self.readings = readings
            self.events = events
            self.ledgerEntries = ledgerEntries
            self.conflicts = conflicts
        }

        enum CodingKeys: String, CodingKey {
            case sessions, readings, events, ledgerEntries = "ledger_entries", conflicts
        }
    }

    public struct FileEntry: Sendable, Hashable, Codable {
        public var name: String
        public var bytes: Int
        public var sha256: String
        public var records: Int

        public init(name: String, bytes: Int, sha256: String, records: Int) {
            self.name = name
            self.bytes = bytes
            self.sha256 = sha256
            self.records = records
        }
    }

    public init(contractVersion: String = Self.contractVersion, schemaVersion: Int = Self.supportedSchemaVersion,
                archiveID: String, createdAt: UTCInstant, producer: Producer, device: Device, snapshot: Snapshot,
                policy: Policy, synthetic: Bool, health: Health, counts: Counts, files: [FileEntry]) {
        self.contractVersion = contractVersion
        self.schemaVersion = schemaVersion
        self.archiveID = archiveID
        self.createdAt = createdAt
        self.producer = producer
        self.device = device
        self.snapshot = snapshot
        self.policy = policy
        self.synthetic = synthetic
        self.health = health
        self.counts = counts
        self.files = files
    }

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case schemaVersion = "schema_version"
        case archiveID = "archive_id"
        case createdAt = "created_at_utc"
        case producer, device, snapshot, policy, synthetic, health, counts, files
    }

    /// Major de `contract_version` si es semver válido (§4, regla de compatibilidad).
    public static func major(ofContractVersion v: String) -> Int? {
        let core = v.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }), p == "0" || p.first != "0",
                  let n = Int(p) else { return nil }
            numbers.append(n)
        }
        return numbers[0]
    }
}

/// Nombre `LingoScan-<producer_tag>-<YYYYMMDDTHHMMSSZ>-<archive_id_8>.lingoscan` (contrato §3).
public struct ArchivePackageName: Sendable, Hashable {
    public static let suffix = ".lingoscan"
    public static let partialSuffix = ".lingoscan.partial"

    public let producerTag: String
    public let createdAt: UTCInstant
    public let archiveID8: String

    public init(producerTag: String, createdAt: UTCInstant, archiveID8: String) {
        self.producerTag = producerTag
        self.createdAt = createdAt
        self.archiveID8 = archiveID8
    }

    public init(producerTag: String, createdAt: UTCInstant, archiveID: String) {
        self.init(producerTag: producerTag, createdAt: createdAt, archiveID8: String(archiveID.prefix(8)))
    }

    /// `YYYYMMDDTHHMMSSZ` (el `created_at_utc` sin guiones ni dos puntos).
    public var timestamp: String {
        createdAt.rfc3339.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
    }

    public var folderName: String { "LingoScan-\(producerTag)-\(timestamp)-\(archiveID8)\(Self.suffix)" }
    public var partialFolderName: String { "LingoScan-\(producerTag)-\(timestamp)-\(archiveID8)\(Self.partialSuffix)" }

    /// Parser estricto del nombre de una carpeta completa (no `.partial`).
    public init?(parsing name: String) {
        guard name.hasSuffix(Self.suffix), name.hasPrefix("LingoScan-") else { return nil }
        let body = name.dropFirst("LingoScan-".count).dropLast(Self.suffix.count)
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let tag = String(parts[0]), ts = String(parts[1]), id8 = String(parts[2])
        guard !tag.isEmpty, tag.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }),
              id8.count == 8, id8.allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase }),
              ts.count == 16, ts.hasSuffix("Z"), ts[ts.index(ts.startIndex, offsetBy: 8)] == "T" else { return nil }
        let t = Array(ts)
        let text = String(t[0..<4]) + "-" + String(t[4..<6]) + "-" + String(t[6..<8]) + "T"
            + String(t[9..<11]) + ":" + String(t[11..<13]) + ":" + String(t[13..<15]) + "Z"
        guard let at = UTCInstant(rfc3339: text) else { return nil }
        self.init(producerTag: tag, createdAt: at, archiveID8: id8)
    }

    public static func isPartial(_ name: String) -> Bool { name.hasSuffix(partialSuffix) }
}
