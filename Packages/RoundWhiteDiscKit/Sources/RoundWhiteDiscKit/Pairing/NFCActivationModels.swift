import Foundation

/// Sensor family derived from the NFC patch info (`0xA1`). Only exact,
/// documented combinations map to a known family; anything else is `.unknown`
/// and must not be activated or paired.
///
/// - `.lingo`: `productType == 9 && securityVersion == 3` (Juggluco 11.5.4,
///   `nfc.cpp:100-105`, `NFC.java:41-49`; see `docs/PROTOCOLO_LINGO.md` §1.3).
/// - `.libre3`: `productType == 4` (captured Libre 3 patch info).
public enum SensorFamily: String, Sendable, Codable, CaseIterable {
    case libre3
    case lingo
    case unknown

    /// The NFC `productType` byte that identifies this family, if any.
    public var productType: UInt8? {
        switch self {
        case .libre3: return 4
        case .lingo: return 9
        case .unknown: return nil
        }
    }

    public init(productType: UInt8, securityVersion: UInt16) {
        switch (productType, securityVersion) {
        case (9, 3): self = .lingo
        case (4, _): self = .libre3
        default: self = .unknown
        }
    }
}

public struct Libre3NFCPatchInfo: Sendable, Equatable {
    public let inputRaw: Data
    public let raw: Data
    public let stateByte: UInt8
    public let productType: UInt8
    public let securityVersion: UInt16
    /// 1 Europe, 2 US, 4 Australia/Canada, 8 eastern rest-of-world (per DiaBLE).
    public let region: UInt16
    public let generation: UInt16
    public let wearDurationMinutes: UInt16
    public let warmupMinutes: UInt16
    public let firmwareVersion: String
    public let serialNumber: String

    /// Size guard (T-02 review, unchanged): the frame after normalisation must
    /// hold at least 29 bytes (`00 A5 00` + 26-byte `firstnfc` struct incl.
    /// CRC). Juggluco uses the same minimum for Lingo (`Libre3.java:42-44`),
    /// so this guard is not expected to reject a Lingo A1 response. Not yet
    /// confirmed with a real Lingo capture.
    public init(raw: Data) throws {
        let frame = Self.normalizeResponse(raw)
        guard frame.count >= 29, frame[0] == 0x00, frame[1] == 0xa5 else {
            throw Libre3NFCError.invalidPatchInfo(raw)
        }
        self.inputRaw = raw
        self.raw = frame
        self.securityVersion = Self.u16(frame, 3)
        self.region = Self.u16(frame, 5)
        self.generation = Self.u16(frame, 7)
        self.wearDurationMinutes = Self.u16(frame, 9)
        self.firmwareVersion = "\(Self.byte(frame, 14)).\(Self.byte(frame, 13)).\(Self.byte(frame, 12)).\(Self.byte(frame, 11))"
        self.productType = Self.byte(frame, 15)
        self.warmupMinutes = UInt16(Self.byte(frame, 16)) * 5
        self.stateByte = Self.byte(frame, 17)
        let serialBytes = frame.subdata(in: (frame.startIndex + 18)..<(frame.startIndex + 27))
        self.serialNumber = String(data: serialBytes, encoding: .ascii) ?? Self.hex(serialBytes)
    }

    public var recommendedCommandCode: NFCActivationCommandCode {
        stateByte == 0x01 ? .activate : .switchReceiver
    }

    /// Family derived from `productType` and `securityVersion`.
    public var family: SensorFamily {
        SensorFamily(productType: productType, securityVersion: securityVersion)
    }
}

private extension Libre3NFCPatchInfo {
    static func normalizeResponse(_ raw: Data) -> Data {
        var frame = raw
        if frame.first == 0xa5 {
            frame = Data([0x00]) + frame
        }
        if frame.count >= 2, frame[0] == 0x00, frame[1] == 0xa5 {
            var bodyStart = 2
            while bodyStart < frame.count, frame[bodyStart] == 0xa5 {
                bodyStart += 1
            }
            if bodyStart > 2 {
                return Data([0x00, 0xa5]) + frame.suffix(from: bodyStart)
            }
            return frame
        }
        return raw
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
    }

    static func byte(_ data: Data, _ offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }
}

public struct Libre3NFCActivationResponse: Sendable, Equatable {
    public let raw: Data
    public let bleAddressLittleEndian: Data
    public let blePIN: Data
    public let activationTimeRaw: Data
    public let trailingCRC: Data

    /// Size guard (T-02 review, unchanged): a successful activation/switch
    /// response is exactly 19 bytes (`struct nfc2` in Juggluco, identical for
    /// Lingo, `nfc.cpp:141-154`). A 4-byte `00 A5 01 <err>` error response
    /// (e.g. `0xB1` account-ID rejection) fails this guard and surfaces as
    /// `invalidActivationResponse` with the raw bytes. Not yet confirmed with
    /// a real Lingo capture.
    public init(raw: Data) throws {
        let frame = Self.normalizeResponse(raw)
        guard frame.count == 19, frame[0] == 0x00, frame[1] == 0xa5, frame[2] == 0x00 else {
            throw Libre3NFCError.invalidActivationResponse(raw)
        }
        self.raw = frame
        self.bleAddressLittleEndian = frame.subdata(in: 3..<9)
        self.blePIN = frame.subdata(in: 9..<13)
        self.activationTimeRaw = frame.subdata(in: 13..<17)
        self.trailingCRC = frame.subdata(in: 17..<19)
    }

    public var bleAddressDisplay: String {
        bleAddressLittleEndian.reversed()
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }

    public func sensorState(
        serialNumber: String?,
        receiverID: Libre3ReceiverID? = nil,
        patchInfo: Libre3NFCPatchInfo? = nil,
        source: String? = "NFC activation response"
    ) throws -> Libre3SensorState {
        try Libre3SensorState(
            serialNumber: serialNumber,
            blePIN: blePIN,
            bleAddress: bleAddressDisplay,
            receiverID: receiverID,
            source: source,
            warmupDurationMinutes: patchInfo.map { Int($0.warmupMinutes) },
            wearDurationMinutes: patchInfo.map { Int($0.wearDurationMinutes) },
            productType: patchInfo?.productType,
            securityVersion: patchInfo?.securityVersion,
            family: patchInfo?.family
        )
    }
}

private extension Libre3NFCActivationResponse {
    static func normalizeResponse(_ raw: Data) -> Data {
        if raw.count >= 2, raw[0] == 0x00, raw[1] == 0xa5 {
            return raw
        }
        if raw.first == 0xa5 {
            return Data([0x00]) + raw
        }
        return raw
    }
}

public struct Libre3NFCScanResult: Sendable, Equatable {
    public let patchInfo: Libre3NFCPatchInfo
    public let commandCode: NFCActivationCommandCode?
    public let commandParameters: Data?
    public let activationResponse: Libre3NFCActivationResponse?

    public init(
        patchInfo: Libre3NFCPatchInfo,
        commandCode: NFCActivationCommandCode? = nil,
        commandParameters: Data? = nil,
        activationResponse: Libre3NFCActivationResponse? = nil
    ) {
        self.patchInfo = patchInfo
        self.commandCode = commandCode
        self.commandParameters = commandParameters
        self.activationResponse = activationResponse
    }
}

public enum Libre3NFCScanMode: Sendable, Equatable {
    case readPatchInfo
    case activateFreshSensor(receiverID: UInt32, timeSeconds: UInt32? = nil)
    case switchReceiver(receiverID: UInt32, timeSeconds: UInt32? = nil)
    case activateOrSwitchReceiver(receiverID: UInt32, timeSeconds: UInt32? = nil)
    case forceActivationCommand(commandCode: NFCActivationCommandCode, receiverID: UInt32, timeSeconds: UInt32? = nil)
}

public enum Libre3NFCError: Error, Sendable, Equatable {
    case readerUnavailable
    case sessionAlreadyActive
    case noTag
    case multipleTags
    case nonISO15693Tag
    case invalidPatchInfo(Data)
    case invalidActivationResponse(Data)
    case invalidActivationResponseForPatch(
        commandCode: NFCActivationCommandCode,
        patchInfo: Libre3NFCPatchInfo,
        raw: Data
    )
    case unexpectedSensorState(patchInfo: Libre3NFCPatchInfo)
}

extension Libre3NFCError: CustomStringConvertible, LocalizedError {
    public var description: String {
        switch self {
        case .readerUnavailable:
            return "readerUnavailable"
        case .sessionAlreadyActive:
            return "sessionAlreadyActive"
        case .noTag:
            return "noTag"
        case .multipleTags:
            return "multipleTags"
        case .nonISO15693Tag:
            return "nonISO15693Tag"
        case .invalidPatchInfo(let data):
            return "invalidPatchInfo(\(data.count) bytes: \(hex(data)))"
        case .invalidActivationResponse(let data):
            return "invalidActivationResponse(\(data.count) bytes: \(hex(data)))"
        case .invalidActivationResponseForPatch(let commandCode, let patchInfo, let raw):
            return String(
                format: "invalidActivationResponse(command=0x%02x raw=%@ patchState=0x%02x serial=%@ patchRaw=%@ patchInputRaw=%@)",
                commandCode.rawValue,
                hex(raw),
                patchInfo.stateByte,
                patchInfo.serialNumber,
                hex(patchInfo.raw),
                hex(patchInfo.inputRaw)
            )
        case .unexpectedSensorState(let patchInfo):
            return String(
                format: "unexpectedSensorState(0x%02x serial=%@ raw=%@ inputRaw=%@)",
                patchInfo.stateByte,
                patchInfo.serialNumber,
                hex(patchInfo.raw),
                hex(patchInfo.inputRaw)
            )
        }
    }

    public var errorDescription: String? {
        description
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
