@testable import LingoCore

/// Series sintéticas de una lectura por minuto para los tests de `Analytics` (T-23). Sin datos reales.
enum AnalyticsSeries {
    static let t0 = UTCInstant(epochSeconds: TestSupport.activationEpoch)

    static func instant(_ minute: Int) -> UTCInstant { t0.adding(seconds: Int64(minute) * 60) }

    /// Una lectura por minuto en `minutes`, con el valor que da `value(minuto)` redondeado.
    static func series(_ minutes: ClosedRange<Int>, _ value: (Int) -> Double) -> [BasicStats.Sample] {
        minutes.map { BasicStats.Sample(measuredAt: instant($0), valueMgdl: Int(value($0).rounded())) }
    }
}
