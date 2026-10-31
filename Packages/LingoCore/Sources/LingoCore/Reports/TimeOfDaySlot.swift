/// Franja del día local: mañana 6–11, mediodía 11–16, tarde 16–22, noche 22–6 (hora de inicio incluida).
public enum TimeOfDaySlot: String, Sendable, Hashable, Codable, CaseIterable {
    case morning
    case midday
    case evening
    case night

    /// Minuto local de inicio (desde medianoche).
    public var startMinute: Int {
        switch self {
        case .morning: 6 * 60
        case .midday: 11 * 60
        case .evening: 16 * 60
        case .night: 22 * 60
        }
    }

    /// Duración en minutos.
    public var lengthMinutes: Int {
        switch self {
        case .morning, .midday: 5 * 60
        case .evening: 6 * 60
        case .night: 8 * 60
        }
    }

    public init(minuteOfDay: Int) {
        switch minuteOfDay {
        case 360..<660: self = .morning
        case 660..<960: self = .midday
        case 960..<1320: self = .evening
        default: self = .night
        }
    }
}
