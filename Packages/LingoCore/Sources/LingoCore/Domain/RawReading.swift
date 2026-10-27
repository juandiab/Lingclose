/// Campos crudos del sensor (`raw`, contrato §5.2). Nunca se modifican tras decodificar.
///
/// Todos son opcionales salvo `qualityFlag`, que el contrato define como booleano nunca nulo.
public struct RawReading: Sendable, Hashable, Codable {
    public var capped: Int?
    public var uncapped: Int?
    public var historicCapped: Int?
    public var historicUncapped: Int?
    public var historicLifeCount: Int?
    public var rateCenti: Int?
    public var trend: Int?
    public var actionable: Bool?
    public var temperatureCenti: Int?
    public var rangeBits: Int?
    public var qualityFlag: Bool
    public var channel: Int?
    public var reservedHex: String?

    public init(
        capped: Int? = nil,
        uncapped: Int? = nil,
        historicCapped: Int? = nil,
        historicUncapped: Int? = nil,
        historicLifeCount: Int? = nil,
        rateCenti: Int? = nil,
        trend: Int? = nil,
        actionable: Bool? = nil,
        temperatureCenti: Int? = nil,
        rangeBits: Int? = nil,
        qualityFlag: Bool,
        channel: Int? = nil,
        reservedHex: String? = nil
    ) {
        self.capped = capped
        self.uncapped = uncapped
        self.historicCapped = historicCapped
        self.historicUncapped = historicUncapped
        self.historicLifeCount = historicLifeCount
        self.rateCenti = rateCenti
        self.trend = trend
        self.actionable = actionable
        self.temperatureCenti = temperatureCenti
        self.rangeBits = rangeBits
        self.qualityFlag = qualityFlag
        self.channel = channel
        self.reservedHex = reservedHex
    }

    /// Equivalencia del contrato §5.2 (C5) y §8.4: todos los campos no nulos **en ambos** coinciden
    /// (incluido `reserved_hex`), `quality_flag` coincide siempre y `channel` si ambos lo traen.
    public func isEquivalent(to other: RawReading) -> Bool {
        guard qualityFlag == other.qualityFlag else { return false }
        return Self.agree(capped, other.capped)
            && Self.agree(uncapped, other.uncapped)
            && Self.agree(historicCapped, other.historicCapped)
            && Self.agree(historicUncapped, other.historicUncapped)
            && Self.agree(historicLifeCount, other.historicLifeCount)
            && Self.agree(rateCenti, other.rateCenti)
            && Self.agree(trend, other.trend)
            && Self.agree(actionable, other.actionable)
            && Self.agree(temperatureCenti, other.temperatureCenti)
            && Self.agree(rangeBits, other.rangeBits)
            && Self.agree(channel, other.channel)
            && Self.agree(reservedHex, other.reservedHex)
    }

    /// `true` si no son equivalentes: dos observaciones distintas del mismo minuto.
    public func isFromDistinctRoute(than other: RawReading) -> Bool { !isEquivalent(to: other) }

    private static func agree<T: Equatable>(_ a: T?, _ b: T?) -> Bool {
        guard let a, let b else { return true }
        return a == b
    }

    enum CodingKeys: String, CodingKey {
        case capped
        case uncapped
        case historicCapped = "historic_capped"
        case historicUncapped = "historic_uncapped"
        case historicLifeCount = "historic_life_count"
        case rateCenti = "rate_centi"
        case trend
        case actionable
        case temperatureCenti = "temperature_centi"
        case rangeBits = "range_bits"
        case qualityFlag = "quality_flag"
        case channel
        case reservedHex = "reserved_hex"
    }

    /// Todas las claves obligatorias se escriben, con `null` explícito; `reserved_hex` es opcional.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(capped, forKey: .capped)
        try c.encode(uncapped, forKey: .uncapped)
        try c.encode(historicCapped, forKey: .historicCapped)
        try c.encode(historicUncapped, forKey: .historicUncapped)
        try c.encode(historicLifeCount, forKey: .historicLifeCount)
        try c.encode(rateCenti, forKey: .rateCenti)
        try c.encode(trend, forKey: .trend)
        try c.encode(actionable, forKey: .actionable)
        try c.encode(temperatureCenti, forKey: .temperatureCenti)
        try c.encode(rangeBits, forKey: .rangeBits)
        try c.encode(qualityFlag, forKey: .qualityFlag)
        try c.encode(channel, forKey: .channel)
        try c.encode(reservedHex, forKey: .reservedHex)
    }
}
