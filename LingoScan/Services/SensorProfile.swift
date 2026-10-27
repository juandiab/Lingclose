import CryptoKit
import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Lo leído por NFC (`0xA1`). El serial completo solo sale por `serialNumber`
/// (Keychain y archivo de recuperación); `description` lo recorta.
struct SensorProfile: Sendable, Equatable, CustomStringConvertible {
    let family: RWDKSensorFamily
    let productType: UInt8
    let securityVersion: UInt16
    private let serial: String
    let warmupMinutes: Int
    let wearMinutes: Int
    let firmwareHex: String
    let stateByte: UInt8
    /// Original NFC patch bytes contain the serial and must remain protected.
    let patchInfoRaw: Data?

    init(
        family: RWDKSensorFamily,
        productType: UInt8,
        securityVersion: UInt16,
        serial: String,
        warmupMinutes: Int,
        wearMinutes: Int,
        firmwareHex: String,
        stateByte: UInt8,
        patchInfoRaw: Data? = nil
    ) {
        self.family = family
        self.productType = productType
        self.securityVersion = securityVersion
        self.serial = serial
        self.warmupMinutes = warmupMinutes
        self.wearMinutes = wearMinutes
        self.firmwareHex = firmwareHex
        self.stateByte = stateByte
        self.patchInfoRaw = patchInfoRaw
    }

    init(patchInfo: Libre3NFCPatchInfo) {
        let frame = patchInfo.raw
        let firmware = frame.count >= 15 ? Data(frame[(frame.startIndex + 11)..<(frame.startIndex + 15)]) : Data()
        self.init(
            family: patchInfo.family,
            productType: patchInfo.productType,
            securityVersion: patchInfo.securityVersion,
            serial: patchInfo.serialNumber,
            warmupMinutes: SensorLifecycle.warmupDurationMinutes(for: patchInfo),
            wearMinutes: SensorLifecycle.wearDurationMinutes(for: patchInfo),
            firmwareHex: firmware.lowercaseHex,
            stateByte: patchInfo.stateByte,
            patchInfoRaw: patchInfo.raw
        )
    }

    /// Serial completo. Solo para Keychain y recuperación; nunca para logs.
    var serialNumber: String { serial }

    var redactedSerial: String { Redactor.serial(serial) }

    /// SHA-256 hex de `"lingoscan-v1:" + serial` (contrato §5.1).
    var serialHash: String {
        Data(SHA256.hash(data: Data(("lingoscan-v1:" + serial).utf8))).lowercaseHex
    }

    /// Variante soportada: `productType == 9 && securityVersion == 3`.
    var isSupportedLingo: Bool { family == .lingo && productType == 9 && securityVersion == 3 }

    /// `state == 1`: sin activar (único estado en que se puede enviar `0xA0`).
    var isFresh: Bool { stateByte == 0x01 }

    /// Estados 6 y 8 del parche: terminado (`docs/PROTOCOLO_LINGO.md` §1.6).
    var isTerminated: Bool { stateByte == 0x06 || stateByte == 0x08 }

    var description: String {
        "SensorProfile(\(family.rawValue), pt \(productType), sv \(securityVersion), serial \(redactedSerial), state \(stateByte))"
    }
}
