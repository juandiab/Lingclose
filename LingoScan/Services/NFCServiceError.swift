import Foundation
import RoundWhiteDiscKit

/// Errores NFC sin bytes crudos ni serial (los errores del fork los incluyen en su descripción).
enum NFCServiceError: Error, Equatable, CustomStringConvertible {
    case readerUnavailable
    case sessionBusy
    case noTag
    /// `head`: hasta 3 primeros bytes en hex; `a5Offset`: primer `A5` (cabecera esperada en 0 o 1).
    /// Nunca incluye el serial (offset ≥ 18 en una trama válida).
    case invalidPatchInfo(length: Int, head: String, a5Offset: Int?)
    case sensorNotFresh
    case ticketRejected
    case activationRejected(code: UInt8, reason: Reason)
    case invalidActivationResponse(length: Int)
    case missingActivationResponse
    case reader(domain: String, code: Int)

    enum Reason: String, Sendable, Equatable {
        case receiverIDRejected
        case sensorTerminated
        case other
    }

    init(_ error: any Error, patchStateByte: UInt8? = nil) {
        switch error {
        case let e as NFCServiceError:
            self = e
        case let e as Libre3NFCActivationError:
            let reason: Reason = switch e.reason(patchStateByte: patchStateByte) {
            case .receiverIDRejected: .receiverIDRejected
            case .sensorTerminated: .sensorTerminated
            case .other: .other
            }
            self = .activationRejected(code: e.code, reason: reason)
        case let e as Libre3NFCError:
            switch e {
            case .readerUnavailable: self = .readerUnavailable
            case .sessionAlreadyActive: self = .sessionBusy
            case .noTag, .multipleTags, .nonISO15693Tag: self = .noTag
            case .invalidPatchInfo(let raw):
                let bytes = [UInt8](raw)
                self = .invalidPatchInfo(
                    length: bytes.count,
                    head: bytes.prefix(3).map { String(format: "%02x", $0) }.joined(separator: " "),
                    a5Offset: bytes.firstIndex(of: 0xA5)
                )
            case .invalidActivationResponse(let raw): self = .invalidActivationResponse(length: raw.count)
            case .invalidActivationResponseForPatch(_, _, let raw): self = .invalidActivationResponse(length: raw.count)
            case .unexpectedSensorState: self = .sensorNotFresh
            }
        default:
            let ns = error as NSError
            self = .reader(domain: ns.domain, code: ns.code)
        }
    }

    var description: String {
        switch self {
        case .readerUnavailable: "NFC no disponible"
        case .sessionBusy: "sesión NFC ocupada"
        case .noTag: "sin etiqueta ISO 15693"
        case .invalidPatchInfo(let n, let head, let a5):
            "patchInfo inválido (\(n) B; inicio \(head.isEmpty ? "vacío" : head); A5 en \(a5.map(String.init) ?? "ninguno"))"
        case .sensorNotFresh: "el sensor no está sin activar (state != 1)"
        case .ticketRejected: "ticket de activación inválido"
        case .activationRejected(let code, let reason): "activación rechazada (código \(code), \(reason.rawValue))"
        case .invalidActivationResponse(let n): "respuesta de activación inválida (\(n) B)"
        case .missingActivationResponse: "sin respuesta de activación"
        case .reader(let domain, let code): "lector NFC: \(domain) #\(code)"
        }
    }
}
