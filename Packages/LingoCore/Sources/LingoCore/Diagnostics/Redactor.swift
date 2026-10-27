import Foundation

/// Redacción para `event_log` (ARQUITECTURA §8). Nunca se escriben claves, PIN ni kAuth:
/// esos pasan por `secret(_:)`, que solo deja la longitud.
public enum Redactor {
    /// Blobs de más de 8 B: 2 primeros y 2 últimos bytes más la longitud (`a1b2…c3d4 (51 B)`).
    /// Hasta 8 B se muestran completos (comandos y respuestas cortas de diagnóstico).
    public static func hex(_ data: Data) -> String {
        let bytes = [UInt8](data)
        guard bytes.count > 8 else { return hexString(bytes[...]) }
        return hexString(bytes[0..<2]) + "…" + hexString(bytes[(bytes.count - 2)...]) + " (\(bytes.count) B)"
    }

    /// Serial: 3 primeros caracteres + `…`. Con 3 o menos caracteres no se muestra nada del serial.
    public static func serial(_ serial: String) -> String {
        guard serial.count > 3 else { return "…" }
        return String(serial.prefix(3)) + "…"
    }

    /// Material secreto (kAuth, PIN, claves): solo la longitud.
    public static func secret(_ data: Data) -> String {
        "‹secreto \(data.count) B›"
    }

    private static func hexString(_ bytes: ArraySlice<UInt8>) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
