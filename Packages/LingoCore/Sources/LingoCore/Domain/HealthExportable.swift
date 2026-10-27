/// Lo único que el exportador de Health puede recibir (contrato §7.6, C6).
///
/// Solo se construye desde una lectura con `synthetic == false`, `deleted == false` y
/// `eligibility.status == .eligible`; el filtro es estructural, no una condición desactivable.
public struct HealthExportable: Sendable, Hashable {
    public let recordID: String
    public let sessionID: String
    public let lifeCount: Int
    public let valueMgdl: Int
    public let measuredAt: UTCInstant
    public let origin: ReadingOrigin
    public let trend: Int?
    /// `HKMetadataKeySyncIdentifier` propuesto: el `record_id` canónico. Si el ledger muestra que el sujeto
    /// ya se escribió con otro identificador (`source_record_id`, §7.3), el exportador debe conservar ese.
    public let syncIdentifier: String
    /// `HKMetadataKeySyncVersion` = `revision`.
    public let syncVersion: Int

    public init?(reading: GlucoseReading) {
        guard !reading.synthetic,
              !reading.deleted,
              reading.eligibility.status == .eligible,
              reading.analyte == .glucose,
              let value = reading.value
        else { return nil }
        recordID = reading.recordID
        sessionID = reading.sessionID
        lifeCount = reading.lifeCount
        valueMgdl = value
        measuredAt = reading.measuredAt
        origin = reading.origin
        trend = reading.raw.trend
        syncIdentifier = reading.recordID
        syncVersion = reading.revision
    }

    /// Además valida la procedencia persistida: la sesión debe ser la de la lectura y no sintética.
    public init?(reading: GlucoseReading, session: SensorSessionRecord) {
        guard session.sessionID == reading.sessionID, !session.synthetic else { return nil }
        self.init(reading: reading)
    }
}
