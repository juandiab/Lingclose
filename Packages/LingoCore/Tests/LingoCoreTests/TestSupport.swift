import Foundation
@testable import LingoCore

/// Utilidades compartidas por los tests. Todo es sintético: sesión, serial y valores inventados,
/// salvo las tramas públicas de Juggluco (`docs/PROTOCOLO_LINGO.md` §8).
enum TestSupport {
    static let appID = "com.otalvaro.lingoscan"
    static let tz = "America/Bogota"
    /// 2026-10-27T12:00:00Z
    static let activationEpoch: Int64 = 1_793_102_400

    static func newID() -> String { UUID().uuidString.lowercased() }

    /// Base en un directorio temporal propio (WAL necesita archivo, no `:memory:`).
    static func temporaryDatabasePath(_ name: String = "store") throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingoCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).sqlite").path
    }

    static func makeStore(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_793_200_000) }) throws -> SQLiteStore {
        try SQLiteStore(path: temporaryDatabasePath(), now: now)
    }

    static func session(id: String = newID(), synthetic: Bool = false, warmup: Int = 60) -> SensorSessionRecord {
        SensorSessionRecord(
            sessionID: id, sensorFamily: .lingo, productType: 9, securityVersion: 3,
            sensorSerialHash: String(repeating: "ab", count: 32), synthetic: synthetic,
            sensorSerialRedacted: "XYZ…", firmwareHex: "01020304", warmupMinutes: warmup, wearMinutes: 20_160,
            activationTimeEpochS: activationEpoch, activationTimeSource: .nfcResponse, activatedByAppID: appID,
            activationSource: .thisApp, activationState: .authenticated, receiverIDPresent: true
        )
    }

    static func raw(uncapped: Int? = nil, capped: Int? = nil, qualityFlag: Bool = false, trend: Int? = nil,
                    temperature: Int? = nil, channel: Int? = nil) -> RawReading {
        RawReading(capped: capped, uncapped: uncapped, trend: trend, temperatureCenti: temperature,
                   qualityFlag: qualityFlag, channel: channel)
    }

    static func reading(_ session: SensorSessionRecord, lc: Int, raw: RawReading, origin: ReadingOrigin,
                        synthetic: Bool? = nil) -> GlucoseReading {
        var r = GlucoseReading.make(session: session, lifeCount: lc, raw: raw, origin: origin,
                                    receivedAt: UTCInstant(epochSeconds: activationEpoch + 60 * Int64(lc) + 2),
                                    tzAtCapture: tz)
        if let synthetic { r.synthetic = synthetic }
        return r
    }
}

/// Convierte una trama de tiempo real Lingo de 51 B (plaintext) en `RawReading`, siguiendo
/// `docs/PROTOCOLO_LINGO.md` §3. Solo para tests: el decodificador real vive en el fork (T-03).
enum LingoFrameFixture {
    struct Decoded {
        let lifeCount: Int
        let raw: RawReading
    }

    static func bytes(_ hex: String) -> [UInt8] {
        let chars = Array(hex.utf8)
        precondition(chars.count % 2 == 0)
        func nibble(_ c: UInt8) -> UInt8 {
            switch c {
            case 0x30...0x39: c - 0x30
            case 0x41...0x46: c - 0x41 + 10
            case 0x61...0x66: c - 0x61 + 10
            default: preconditionFailure("hex inválido")
            }
        }
        return stride(from: 0, to: chars.count, by: 2).map { nibble(chars[$0]) << 4 | nibble(chars[$0 + 1]) }
    }

    static func decode(_ hex: String) -> Decoded {
        let b = bytes(hex)
        precondition(b.count == 51, "la trama Lingo mide 51 B")
        func u16(_ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
        func reading(_ w: UInt16) -> Int? { w & 0x8000 != 0 ? nil : Int(w & 0x0FFF) }
        let lc = Int(u16(0))
        let historicLC = Int(u16(2))
        let typemap = b[34]
        let types = [typemap & 0x0F, typemap >> 4]
        let temperatureWord = u16(37)
        let reserved = b[35..<51].map { String(format: "%02x", $0) }.joined()
        guard let channel = types.firstIndex(of: 1) else {
            return Decoded(lifeCount: lc, raw: RawReading(historicLifeCount: historicLC, qualityFlag: true, reservedHex: reserved))
        }
        let base = 4 + 15 * channel
        let cappedW = u16(base), uncappedW = u16(base + 11)
        let rate = Int16(bitPattern: u16(base + 2))
        let trendByte = b[base + 10]
        var trend = Int(trendByte & 0x07)
        if trend > 5 { trend = 0 }
        // Bit 15 de la palabra de la que sale el valor (uncapped; si es inválida, capped).
        let quality = uncappedW & 0x8000 != 0 && cappedW & 0x8000 != 0
        let raw = RawReading(
            capped: reading(cappedW),
            uncapped: reading(uncappedW),
            historicCapped: reading(u16(base + 8)),
            historicUncapped: reading(u16(base + 13)),
            historicLifeCount: historicLC,
            rateCenti: rate == Int16.min ? nil : Int(rate),
            trend: trend,
            actionable: trendByte & 0x08 != 0,
            temperatureCenti: temperatureWord == 0x8000 ? nil : Int(temperatureWord),
            rangeBits: Int((cappedW & 0x6000) >> 13),
            qualityFlag: quality,
            channel: channel,
            reservedHex: reserved
        )
        return Decoded(lifeCount: lc, raw: raw)
    }

    // docs/PROTOCOLO_LINGO.md §8.1 (warm-up, lc 1..4)
    static let warmUp = [
        "01000000008000800000ffff00800800800080208000800000ffff0080082080008010000000806d00110cba49680f00080000",
        "02000000008000800000ffff00800800800080208000800000ffff00800820800080100000008070000807b1494f0e00000000",
        "03000000008000800000ffff00800800800080208000800000ffff00800820800080100000008070001606ec491c0e00000000",
        "04000000008000800000ffff00800800800080008000800000ffff0080080080008010000000807000d805fe490d0e00000000",
    ]
    // §8.2 (calentado, lc 58 y 63)
    static let warmLC58 = "3a002800008000800000ffff00800800800080c94000800000ffff008008c9000080100000d30c7000b808764de60e00000000"
    static let warmLC63 = "3f002d00008000800000ffff00800800800080c94000800000ffff008008d0000080100000b90c70000109e14ced0e00000000"
    // §8.3 (rate/trend); el sexto es warm lc58. (hex, rate, trend, mg/dL esperado)
    static let trends: [(hex: String, rate: Int?, trend: Int, mgdl: Int)] = [
        ("0938F5370080EDFF0000FFFF00800B008000809D00EDFF0000283C9C000B9D009C0010000000806E0024074F48091100080000", -19, 3, 157),
        ("4438313800808EFF0000FFFF00800A0080008089008EFF0000E02EAC000A8900AC001000000F0C7000C90609495D1000000000", -114, 2, 137),
        ("49383638008034FF0000FFFF00800900800080780034FF0000C422A300097800A300100000100C710063060F49E70F00000000", -204, 1, 120),
        ("BB3AA73A008000010000FFFF00800D008000809E0000010000904C63000D9E006300100000040B70004F052243F41100000000", 256, 5, 158),
        ("473B333B008000800000FFFF00800B008000809B0000800000FFFFC3000B9B00C300100000320C7100F007D3497C1100000000", nil, 3, 155),
        (warmLC58, nil, 0, 201),
    ]
}
