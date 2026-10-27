import Foundation
import RoundWhiteDiscKit

/// NFC sobre `Libre3NFCActivationReader` del fork. Dos operaciones sin fallback
/// entre sí: lectura (`0xA1`) y activación de un sensor nuevo (`0xA0`). Los modos
/// de cambio de receptor del fork no se usan en este módulo (test de grep).
actor NFCService: SensorNFC {
    private let reader = Libre3NFCActivationReader()

    func readPatchInfo() async throws -> SensorProfile {
        do {
            let scan = try await reader.scan(mode: .readPatchInfo)
            return SensorProfile(patchInfo: scan.patchInfo)
        } catch {
            throw NFCServiceError(error)
        }
    }

    func activate(ticket: ActivationTicket) async throws -> ActivationResponse {
        // Defensa en profundidad: la fábrica ya lo exige.
        guard ticket.profile.isSupportedLingo, ticket.profile.isFresh, ticket.receiverID != 0 else {
            throw NFCServiceError.ticketRejected
        }
        do {
            // El lector relee 0xA1 y solo envía 0xA0 si state == 1
            // (`CoreNFCActivationReader.swift`, rama de sensor nuevo).
            let scan = try await reader.scan(mode: .activateFreshSensor(receiverID: ticket.receiverID, timeSeconds: nil))
            return try ActivationResponse(scan: scan)
        } catch {
            throw NFCServiceError(error, patchStateByte: ticket.profile.stateByte)
        }
    }
}
