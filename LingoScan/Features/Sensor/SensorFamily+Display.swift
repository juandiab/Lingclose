import LingoCore

extension SensorFamily {
    /// Nombre para mostrar. "Lingo" es un producto de bienestar de Abbott; no se afirma nada clínico.
    var displayName: String {
        switch self {
        case .lingo: String(localized: "sensor.family.lingo", defaultValue: "Abbott Lingo")
        case .libre3: String(localized: "sensor.family.libre3", defaultValue: "FreeStyle Libre 3")
        case .unknown: String(localized: "sensor.family.unknown", defaultValue: "Desconocido")
        }
    }
}
