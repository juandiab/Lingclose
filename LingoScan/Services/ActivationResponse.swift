import Foundation
import RoundWhiteDiscKit

/// Respuesta de éxito a `0xA0` (19 B, `docs/PROTOCOLO_LINGO.md` §1.6) más lo que el
/// lector volvió a leer con `0xA1` en la misma sesión NFC. `description` no muestra secretos.
struct ActivationResponse: Sendable, Equatable, CustomStringConvertible {
    let raw: Data
    let pin: Data
    let bleAddress: String
    /// `activationTime` u32 LE de la respuesta; `nil` si es 0.
    let activationTimeEpochS: Int64?
    /// Serial y estado leídos en la misma sesión, antes del `0xA0`.
    let scannedSerial: String
    let scannedStateByte: UInt8

    init(raw: Data, pin: Data, bleAddress: String, activationTimeEpochS: Int64?, scannedSerial: String, scannedStateByte: UInt8) {
        self.raw = raw
        self.pin = pin
        self.bleAddress = bleAddress
        self.activationTimeEpochS = activationTimeEpochS
        self.scannedSerial = scannedSerial
        self.scannedStateByte = scannedStateByte
    }

    init(scan: Libre3NFCScanResult) throws {
        guard let response = scan.activationResponse else {
            throw NFCServiceError.missingActivationResponse
        }
        let t = response.activationTimeRaw
        var seconds: UInt32 = 0
        for (i, byte) in t.prefix(4).enumerated() { seconds |= UInt32(byte) << (8 * UInt32(i)) }
        self.init(
            raw: response.raw,
            pin: response.blePIN,
            bleAddress: response.bleAddressDisplay,
            activationTimeEpochS: seconds == 0 ? nil : Int64(seconds),
            scannedSerial: scan.patchInfo.serialNumber,
            scannedStateByte: scan.patchInfo.stateByte
        )
    }

    var description: String { "ActivationResponse(\(raw.count) B, ‹redactado›)" }
}
