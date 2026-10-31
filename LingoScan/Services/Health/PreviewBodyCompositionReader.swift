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

    /// Una pesada cada 3 días con valores inventados (peso, grasa, masa magra y cintura; IMC con 1,66 m).
    func bodyMeasurementSeries(from: Date, to: Date) async -> BodyMeasurementSeries {
        var series = BodyMeasurementSeries()
        var day = from.addingTimeInterval(8 * 3_600)
        var index = 0
        while day < to {
            let drift = Double(index) * -0.15
            let weight = 63.8 + drift
            series.samples[.weight, default: []].append(BodyMeasurement(date: day, value: (weight * 10).rounded() / 10))
            series.samples[.bodyFat, default: []].append(BodyMeasurement(date: day, value: (280 + drift * 12).rounded() / 10))
            series.samples[.leanMass, default: []].append(BodyMeasurement(date: day, value: ((weight * 0.72) * 10).rounded() / 10))
            series.samples[.bmi, default: []].append(BodyMeasurement(date: day, value: (weight / (1.66 * 1.66) * 10).rounded() / 10))
            series.samples[.waist, default: []].append(BodyMeasurement(date: day, value: (76 + drift).rounded()))
            day = day.addingTimeInterval(3 * 86_400)
            index += 1
        }
        return series
    }
}
