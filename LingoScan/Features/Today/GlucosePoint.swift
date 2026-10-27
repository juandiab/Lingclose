import Foundation
import LingoCore

/// Punto de la curva: solo lecturas elegibles con valor.
struct GlucosePoint: Sendable, Hashable, Identifiable {
    let id: String
    let sessionID: String
    let lifeCount: Int
    let date: Date
    let value: Int

    init?(_ reading: GlucoseReading) {
        guard reading.analyte == .glucose,
              !reading.deleted,
              reading.eligibility.isEligible,
              let value = reading.value
        else { return nil }
        self.id = reading.recordID
        self.sessionID = reading.sessionID
        self.lifeCount = reading.lifeCount
        self.date = reading.measuredAt.date
        self.value = value
    }

    init(id: String, sessionID: String, lifeCount: Int, date: Date, value: Int) {
        self.id = id
        self.sessionID = sessionID
        self.lifeCount = lifeCount
        self.date = date
        self.value = value
    }
}
