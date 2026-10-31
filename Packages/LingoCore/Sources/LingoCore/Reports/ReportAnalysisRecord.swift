/// Fila de `report_analyses` (migración v4, T-27a): un análisis por IA de un período. Local: no entra en el
/// `.lingoscan`. `requestSHA256` es el hash hex del cuerpo enviado (para reconocer peticiones repetidas sin
/// guardar el snapshot). `responseJSON` es la respuesta estructurada tal cual, sin datos de entrada.
public struct ReportAnalysisRecord: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let createdAt: UTCInstant
    public let periodStart: UTCInstant
    public let periodEnd: UTCInstant
    public let provider: String
    public let model: String
    public let requestSHA256: String
    public let responseJSON: String?
    public let status: ReportAnalysisStatus
    public let error: String?

    public init(id: String, createdAt: UTCInstant, periodStart: UTCInstant, periodEnd: UTCInstant, provider: String,
                model: String, requestSHA256: String, responseJSON: String?, status: ReportAnalysisStatus, error: String?) {
        self.id = id
        self.createdAt = createdAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.provider = provider
        self.model = model
        self.requestSHA256 = requestSHA256
        self.responseJSON = responseJSON
        self.status = status
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case provider, model
        case requestSHA256 = "request_sha256"
        case responseJSON = "response_json"
        case status, error
    }
}
