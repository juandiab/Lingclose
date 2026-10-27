import Foundation

/// Plaintexts Lingo sintéticos con el layout de `docs/PROTOCOLO_LINGO.md` §3 y §4.
enum LingoTestFrames {
    /// 51 B; canal 0 inactivo, canal 1 glucosa (mapa de tipos `0x10`).
    static func realtime(lifeCount: UInt16, mgdl: UInt16, flagged: Bool = false,
                         historicLifeCount: UInt16 = 0, historicMgdl: UInt16 = 0) -> Data {
        var bytes = [UInt8](repeating: 0, count: 51)
        put(&bytes, 0, lifeCount)
        put(&bytes, 2, historicLifeCount)
        let block = 19
        let word = mgdl | (flagged ? 0x8000 : 0)
        put(&bytes, block + 0, word)
        put(&bytes, block + 2, UInt16(bitPattern: 25))
        put(&bytes, block + 8, historicMgdl)
        bytes[block + 10] = 3
        put(&bytes, block + 11, word)
        put(&bytes, block + 13, historicMgdl)
        bytes[34] = 0x10
        put(&bytes, 37, 3150)
        return Data(bytes)
    }

    /// 14 B (Lingo): `patchState` y `currentLifeCount`.
    static func patchStatus(currentLifeCount: Int16, patchState: Int8 = 4) -> Data {
        var bytes = [UInt8](repeating: 0, count: 14)
        put(&bytes, 0, UInt16(bitPattern: currentLifeCount))
        bytes[7] = UInt8(bitPattern: patchState)
        put(&bytes, 8, UInt16(bitPattern: currentLifeCount))
        return Data(bytes)
    }

    private static func put(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8(value >> 8)
    }
}
