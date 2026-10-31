import Foundation

/// `BodyCompositionReading` sintético (valores inventados) para pruebas y previsualizaciones. Nunca toca Apple Salud.
struct PreviewBodyCompositionReader: BodyCompositionReading {
    var fixed: BodyComposition?

    init(_ fixed: BodyComposition? = nil) {
        self.fixed = fixed
    }

    func requestAuthorization() async {}

    func bodyComposition(from: Date, to: Date, timeZone: TimeZone) async -> BodyComposition {
        if let fixed { return fixed }
        let start = from.addingTimeInterval(86_400)
        let end = to.addingTimeInterval(-3_600)
        return BodyComposition.make(
            latest: [.weight: BodyMeasurement(date: end, value: 63.1), .bodyFat: BodyMeasurement(date: end, value: 27.4),
                     .leanMass: BodyMeasurement(date: end, value: 45.8), .waist: BodyMeasurement(date: end, value: 76)],
            inPeriod: [.weight: [BodyMeasurement(date: start, value: 63.8), BodyMeasurement(date: end, value: 63.1)],
                       .bodyFat: [BodyMeasurement(date: start, value: 28.0), BodyMeasurement(date: end, value: 27.4)]],
            timeZone: timeZone)
    }
}
