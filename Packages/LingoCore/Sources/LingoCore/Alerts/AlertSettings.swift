/// Ajustes de alertas (T-24). Los umbrales alto y bajo no se guardan aquí: son las líneas del rango de referencia
/// y se pasan al evaluar. Valores por defecto en D-26. La decodificación tolera campos ausentes (versiones futuras).
public struct AlertSettings: Sendable, Hashable, Codable {
    public static let rateThresholdRange: ClosedRange<Double> = 1.0...4.0
    public static let noDataRange = 10...60
    public static let cooldownChoices = [15, 30, 60]

    /// Interruptor general. Apagado por defecto: al encenderlo la app pide permiso de notificaciones.
    public var isEnabled: Bool
    /// Interruptor por tipo; un tipo ausente cuenta como activo.
    public var kindEnabled: [AlertKind: Bool]
    /// Pendiente mínima, en mg/dL por minuto, para subida o bajada rápida.
    public var rateThreshold: Double
    /// Ventana para la pendiente, en minutos.
    public var rateWindowMinutes: Int
    /// Minutos sin lectura elegible (con la sesión activa) para avisar "sin datos".
    public var noDataAfterMinutes: Int
    /// Silencio entre avisos del mismo tipo mientras la condición se mantiene.
    public var cooldownMinutes: [AlertKind: Int]
    /// Horas de silencio en hora local; `nil` = sin silencio.
    public var quietHours: QuietHours?
    /// La alerta baja suena también en horas de silencio.
    public var lowOverridesQuietHours: Bool

    public init(
        isEnabled: Bool = false,
        kindEnabled: [AlertKind: Bool] = [:],
        rateThreshold: Double = 2.0,
        rateWindowMinutes: Int = 15,
        noDataAfterMinutes: Int = 20,
        cooldownMinutes: [AlertKind: Int] = [:],
        quietHours: QuietHours? = nil,
        lowOverridesQuietHours: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.kindEnabled = kindEnabled
        self.rateThreshold = rateThreshold
        self.rateWindowMinutes = rateWindowMinutes
        self.noDataAfterMinutes = noDataAfterMinutes
        self.cooldownMinutes = cooldownMinutes
        self.quietHours = quietHours
        self.lowOverridesQuietHours = lowOverridesQuietHours
    }

    public static let `default` = AlertSettings()

    public func isEnabled(_ kind: AlertKind) -> Bool { kindEnabled[kind] ?? true }

    public mutating func setEnabled(_ enabled: Bool, for kind: AlertKind) { kindEnabled[kind] = enabled }

    public func cooldown(for kind: AlertKind) -> Int { cooldownMinutes[kind] ?? kind.defaultCooldownMinutes }

    public mutating func setCooldown(_ minutes: Int, for kind: AlertKind) { cooldownMinutes[kind] = minutes }

    /// Acota cada valor a lo editable: pendiente 1,0–4,0 en pasos de 0,5, "sin datos" 10–60 min, ventana 10–30 min,
    /// silencio entre avisos 5–240 min.
    public func normalized() -> AlertSettings {
        var s = self
        let r = Self.rateThresholdRange
        s.rateThreshold = (min(max(rateThreshold.isFinite ? rateThreshold : 2.0, r.lowerBound), r.upperBound) * 2).rounded() / 2
        s.noDataAfterMinutes = min(max(noDataAfterMinutes, Self.noDataRange.lowerBound), Self.noDataRange.upperBound)
        s.rateWindowMinutes = min(max(rateWindowMinutes, 10), 30)
        s.cooldownMinutes = cooldownMinutes.mapValues { min(max($0, 5), 240) }
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, kindEnabled, rateThreshold, rateWindowMinutes, noDataAfterMinutes, cooldownMinutes,
             quietHours, lowOverridesQuietHours
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        kindEnabled = try c.decodeIfPresent([AlertKind: Bool].self, forKey: .kindEnabled) ?? d.kindEnabled
        rateThreshold = try c.decodeIfPresent(Double.self, forKey: .rateThreshold) ?? d.rateThreshold
        rateWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .rateWindowMinutes) ?? d.rateWindowMinutes
        noDataAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .noDataAfterMinutes) ?? d.noDataAfterMinutes
        cooldownMinutes = try c.decodeIfPresent([AlertKind: Int].self, forKey: .cooldownMinutes) ?? d.cooldownMinutes
        quietHours = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours)
        lowOverridesQuietHours = try c.decodeIfPresent(Bool.self, forKey: .lowOverridesQuietHours) ?? d.lowOverridesQuietHours
    }
}
