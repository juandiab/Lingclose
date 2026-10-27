import Foundation

/// Error de una acción del sensor en texto neutro para un `alert`. Sin bytes ni serial.
struct SensorActionFailure: Error, Sendable, Hashable {
    let title: String
    let message: String

    /// Traduce errores NFC, del coordinador o de la fábrica de tickets.
    init(_ error: any Error) {
        if let failure = error as? SensorActionFailure {
            self = failure
            return
        }
        switch error {
        case let nfc as NFCServiceError:
            self = Self.nfc(nfc)
        case is ActivationTicketError:
            self.init(
                title: String(localized: "sensor.error.ticket.title", defaultValue: "Activación no autorizada"),
                message: String(localized: "sensor.error.ticket.message", defaultValue: "La sesión preparada no coincide con el sensor leído. Vuelve a leer el sensor.")
            )
        case is SensorSessionCoordinatorError:
            self.init(
                title: String(localized: "sensor.error.state.title", defaultValue: "Acción no disponible"),
                message: String(localized: "sensor.error.state.message", defaultValue: "El sensor no está en el estado necesario para esta acción. Vuelve a leerlo.")
            )
        default:
            self.init(
                title: String(localized: "sensor.error.generic.title", defaultValue: "No se pudo completar"),
                message: String(describing: type(of: error))
            )
        }
    }

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    /// `NFCReaderError` llega como `.reader(domain: "NFCError", code:)`: 200 cancelada, 201 tiempo agotado.
    private static func nfc(_ error: NFCServiceError) -> SensorActionFailure {
        switch error {
        case .reader(let domain, let code) where domain == "NFCError" && code == 200:
            SensorActionFailure(
                title: String(localized: "sensor.error.cancelled.title", defaultValue: "Lectura cancelada"),
                message: String(localized: "sensor.error.cancelled.message", defaultValue: "Se cerró la sesión NFC antes de leer el sensor. No se envió nada.")
            )
        case .reader(let domain, let code) where domain == "NFCError" && code == 201:
            SensorActionFailure(
                title: String(localized: "sensor.error.timeout.title", defaultValue: "Tiempo agotado"),
                message: String(localized: "sensor.error.timeout.message", defaultValue: "La sesión NFC expiró sin encontrar el sensor.")
            )
        case .noTag:
            SensorActionFailure(
                title: String(localized: "sensor.error.noTag.title", defaultValue: "Sensor no encontrado"),
                message: String(localized: "sensor.error.noTag.message", defaultValue: "Acerca la parte superior del iPhone al sensor y mantenlo quieto.")
            )
        case .invalidPatchInfo, .invalidActivationResponse, .missingActivationResponse:
            SensorActionFailure(
                title: String(localized: "sensor.error.invalid.title", defaultValue: "Respuesta no válida"),
                message: String(localized: "sensor.error.invalid.message", defaultValue: "El sensor respondió con datos que no se pudieron interpretar. Inténtalo de nuevo.")
            )
        case .readerUnavailable:
            SensorActionFailure(
                title: String(localized: "sensor.error.unavailable.title", defaultValue: "NFC no disponible"),
                message: String(localized: "sensor.error.unavailable.message", defaultValue: "Este dispositivo no puede leer NFC (el simulador no tiene NFC).")
            )
        case .sessionBusy:
            SensorActionFailure(
                title: String(localized: "sensor.error.busy.title", defaultValue: "Lector ocupado"),
                message: String(localized: "sensor.error.busy.message", defaultValue: "Ya hay una sesión NFC abierta. Espera a que termine.")
            )
        default:
            SensorActionFailure(
                title: String(localized: "sensor.error.nfc.title", defaultValue: "No se pudo leer el sensor"),
                message: error.description
            )
        }
    }
}
