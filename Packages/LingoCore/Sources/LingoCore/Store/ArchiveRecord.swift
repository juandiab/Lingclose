/// Paquete `.lingoscan` propio, registrado tras el renombrado atómico (contrato §3.1 paso 6).
public struct ArchiveRecord: Sendable, Hashable {
    public var archiveID: String
    public var createdAt: UTCInstant
    public var path: String
    public var readings: Int
    public var manifestSHA256: String
    public var verified: Bool

    public init(archiveID: String, createdAt: UTCInstant, path: String, readings: Int, manifestSHA256: String, verified: Bool) {
        self.archiveID = archiveID
        self.createdAt = createdAt
        self.path = path
        self.readings = readings
        self.manifestSHA256 = manifestSHA256
        self.verified = verified
    }
}
