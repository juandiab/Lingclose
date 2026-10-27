import Foundation
import LingoCore

/// Lo que la UI muestra de un sensor leído o emparejado. Sin secretos: el Receiver ID llega ya recortado.
struct SensorPresentationProfile: Sendable, Hashable {
    var family: SensorFamily
    var productType: Int
    var securityVersion: Int
    /// Fin del calentamiento; `nil` si no hay sesión activa.
    var warmupEndsAt: Date?
    /// Fin de la vida útil del sensor; `nil` si no hay sesión activa.
    var sessionEndsAt: Date?
    var lastConnection: Date?
    /// Receiver ID parcial (por ejemplo "••••A3F2"); nunca completo.
    var receiverIDPartial: String?
    /// Serial recortado (`Redactor.serial`); nunca completo.
    var serialRedacted: String?
    /// Calentamiento y vida útil declarados por el sensor (NFC `0xA1`), en minutos.
    var warmupMinutes: Int?
    var wearMinutes: Int?
    /// `state` del parche leído por NFC; `nil` si no viene de una lectura.
    var stateByte: Int?
    /// `true` para datos de previsualización.
    var synthetic = false

    /// Solo Lingo con `productType == 9` y `securityVersion == 3` se considera compatible.
    var isSupportedVariant: Bool {
        family == .lingo && productType == 9 && securityVersion == 3
    }

    /// Calentamiento que falta a las `now`; `nil` si ya terminó o no aplica.
    func warmupRemaining(at now: Date) -> Duration? {
        guard let warmupEndsAt, warmupEndsAt > now else { return nil }
        return .seconds(warmupEndsAt.timeIntervalSince(now))
    }

    /// Días completos que quedan de vida útil (redondeo hacia arriba); `nil` si no aplica.
    func daysRemaining(at now: Date) -> Int? {
        guard let sessionEndsAt else { return nil }
        let seconds = sessionEndsAt.timeIntervalSince(now)
        return seconds > 0 ? Int((seconds / 86_400).rounded(.up)) : 0
    }
}
