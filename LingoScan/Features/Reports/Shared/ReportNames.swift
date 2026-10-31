import LingoCore

/// Nombres de franjas, tramos y bandas para la interfaz de Reportes.
enum ReportNames {
    static func slot(_ slot: TimeOfDaySlot) -> String {
        switch slot {
        case .morning: String(localized: "reports.slot.morning", defaultValue: "Mañana")
        case .midday: String(localized: "reports.slot.midday", defaultValue: "Mediodía")
        case .evening: String(localized: "reports.slot.evening", defaultValue: "Tarde")
        case .night: String(localized: "reports.slot.night", defaultValue: "Noche")
        }
    }

    /// "6–11 h".
    static func slotHours(_ slot: TimeOfDaySlot) -> String {
        let start = slot.startMinute / 60
        let end = (slot.startMinute + slot.lengthMinutes) / 60 % 24
        return String(localized: "reports.slot.hours", defaultValue: "\(start)–\(end) h")
    }

    static func carbs(_ bucket: CarbBucket) -> String {
        switch bucket {
        case .unknown: String(localized: "reports.carbs.unknown", defaultValue: "Sin carbohidratos anotados")
        case .under20: String(localized: "reports.carbs.under20", defaultValue: "Menos de 20 g")
        case .from20To45: String(localized: "reports.carbs.20to45", defaultValue: "20–45 g")
        case .from45To75: String(localized: "reports.carbs.45to75", defaultValue: "45–75 g")
        case .atLeast75: String(localized: "reports.carbs.75plus", defaultValue: "75 g o más")
        }
    }

    static func duration(_ bucket: DurationBucket) -> String {
        switch bucket {
        case .unspecified: String(localized: "reports.duration.unspecified", defaultValue: "Sin duración")
        case .under30: String(localized: "reports.duration.under30", defaultValue: "Menos de 30 min")
        case .from30To60: String(localized: "reports.duration.30to60", defaultValue: "30–60 min")
        case .atLeast60: String(localized: "reports.duration.60plus", defaultValue: "60 min o más")
        }
    }

    static func band(_ band: GlucoseBand) -> String {
        switch band {
        case .low: String(localized: "reports.band.low", defaultValue: "Bajo")
        case .inRange: String(localized: "reports.band.inRange", defaultValue: "En rango")
        case .high: String(localized: "reports.band.high", defaultValue: "Alto")
        case .veryHigh: String(localized: "reports.band.veryHigh", defaultValue: "Muy alto")
        }
    }

    /// Límites de la banda con el rango del usuario: "< 70", "70–140", "141–250", "> 250".
    static func bandLimits(_ band: GlucoseBand, configuration: ReportConfiguration) -> String {
        switch band {
        case .low: "< \(configuration.rangeLow)"
        case .inRange: "\(configuration.rangeLow)–\(configuration.rangeHigh)"
        case .high: "\(configuration.rangeHigh + 1)–\(configuration.veryHighThreshold)"
        case .veryHigh: "> \(configuration.veryHighThreshold)"
        }
    }

    /// Ventana de noche: "de 11:00 p. m. a 7:00 a. m.".
    static func nightWindow(_ configuration: ReportConfiguration) -> String {
        String(
            localized: "reports.night.window",
            defaultValue: "de \(ReportFormat.clock(minute: configuration.nightStartMinute)) a \(ReportFormat.clock(minute: configuration.nightEndMinute))")
    }
}
