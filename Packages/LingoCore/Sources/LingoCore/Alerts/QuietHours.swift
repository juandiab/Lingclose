/// Franja diaria de silencio en hora local, en minutos desde la medianoche (0…1439). Si `startMinute > endMinute`
/// la franja cruza la medianoche (p. ej. 22:00–07:00). Inicio incluido, fin excluido; inicio == fin = vacía.
public struct QuietHours: Sendable, Hashable, Codable {
    public static let minutesPerDay = 1440

    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = Self.wrap(startMinute)
        self.endMinute = Self.wrap(endMinute)
    }

    /// 22:00–07:00.
    public static let night = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)

    public func contains(minuteOfDay minute: Int) -> Bool {
        let m = Self.wrap(minute)
        if startMinute == endMinute { return false }
        if startMinute < endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute
    }

    static func wrap(_ minute: Int) -> Int {
        let r = minute % minutesPerDay
        return r < 0 ? r + minutesPerDay : r
    }
}
