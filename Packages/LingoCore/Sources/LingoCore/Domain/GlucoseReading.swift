/// Lectura según el contrato §5.2 (una línea de `readings.ndjson`).
public struct GlucoseReading: Sendable, Hashable, Codable {
    public var recordID: String
    /// `record_id` con el que entró desde un paquete ajeno antes de traducir un alias (C1).
    public var sourceRecordID: String?
    public var sessionID: String
    public var lifeCount: Int
    public var analyte: Analyte
    public var unit: String
    public var measuredAt: UTCInstant
    public var receivedAt: UTCInstant
    public var tzAtCapture: String
    public var origin: ReadingOrigin
    /// Valor seleccionado por la política; `nil` si excluida o borrada.
    public var value: Int?
    public var raw: RawReading
    public var eligibility: Eligibility
    public var decoder: DecoderInfo
    public var synthetic: Bool
    public var deleted: Bool
    public var revision: Int
    public var importedFrom: ImportedFrom?

    public init(
        sessionID: String,
        lifeCount: Int,
        analyte: Analyte = .glucose,
        unit: String = "mg/dL",
        measuredAt: UTCInstant,
        receivedAt: UTCInstant,
        tzAtCapture: String,
        origin: ReadingOrigin,
        value: Int?,
        raw: RawReading,
        eligibility: Eligibility,
        decoder: DecoderInfo = .lingoScan,
        synthetic: Bool,
        deleted: Bool = false,
        revision: Int = 1,
        importedFrom: ImportedFrom? = nil,
        sourceRecordID: String? = nil
    ) {
        self.recordID = RecordID.make(sessionID: sessionID, analyte: analyte, lifeCount: lifeCount)
        self.sourceRecordID = sourceRecordID
        self.sessionID = sessionID
        self.lifeCount = lifeCount
        self.analyte = analyte
        self.unit = unit
        self.measuredAt = measuredAt
        self.receivedAt = receivedAt
        self.tzAtCapture = tzAtCapture
        self.origin = origin
        self.value = value
        self.raw = raw
        self.eligibility = eligibility
        self.decoder = decoder
        self.synthetic = synthetic
        self.deleted = deleted
        self.revision = revision
        self.importedFrom = importedFrom
    }

    /// Construye una lectura nueva de esta app: hora por la regla única, `synthetic` heredado de la
    /// sesión y elegibilidad/valor por `lingoscan-v1`.
    public static func make(
        session: SensorSessionRecord,
        lifeCount: Int,
        raw: RawReading,
        origin: ReadingOrigin,
        receivedAt: UTCInstant,
        tzAtCapture: String,
        decoder: DecoderInfo = .lingoScan
    ) -> GlucoseReading {
        let eligibility = LingoScanV1Policy.evaluate(
            raw: raw, lifeCount: lifeCount, warmupMinutes: session.warmupMinutes,
            synthetic: session.synthetic, deleted: false
        )
        return GlucoseReading(
            sessionID: session.sessionID,
            lifeCount: lifeCount,
            measuredAt: MeasuredAt.compute(activationEpoch: session.activationTimeEpochS, lifeCount: lifeCount),
            receivedAt: receivedAt,
            tzAtCapture: tzAtCapture,
            origin: origin,
            value: LingoScanV1Policy.value(for: raw, eligibility: eligibility),
            raw: raw,
            eligibility: eligibility,
            decoder: decoder,
            synthetic: session.synthetic
        )
    }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case sourceRecordID = "source_record_id"
        case sessionID = "session_id"
        case lifeCount = "life_count"
        case analyte, unit
        case measuredAt = "measured_at_utc"
        case receivedAt = "received_at_utc"
        case tzAtCapture = "tz_at_capture"
        case origin, value, raw, eligibility, decoder, synthetic, deleted, revision
        case importedFrom = "imported_from"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recordID, forKey: .recordID)
        try c.encode(sourceRecordID, forKey: .sourceRecordID)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(lifeCount, forKey: .lifeCount)
        try c.encode(analyte, forKey: .analyte)
        try c.encode(unit, forKey: .unit)
        try c.encode(measuredAt, forKey: .measuredAt)
        try c.encode(receivedAt, forKey: .receivedAt)
        try c.encode(tzAtCapture, forKey: .tzAtCapture)
        try c.encode(origin, forKey: .origin)
        try c.encode(value, forKey: .value)
        try c.encode(raw, forKey: .raw)
        try c.encode(eligibility, forKey: .eligibility)
        try c.encode(decoder, forKey: .decoder)
        try c.encode(synthetic, forKey: .synthetic)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(revision, forKey: .revision)
        try c.encode(importedFrom, forKey: .importedFrom)
    }
}
