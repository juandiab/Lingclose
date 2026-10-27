import Foundation

/// Normalización de la frase de recuperación según `LingoScan_Shared/RECUPERACION_V1.md` §3.1 (C8).
///
/// Orden fijo: (1) Unicode NFC de la cadena completa; (2) recorte **solo en los bordes** de los
/// escalares de `trimSet` (propiedad Unicode `White_Space`); (3) UTF-8 sin BOM.
/// No se recortan U+200B, U+200C, U+200D, U+FEFF ni U+001C–U+001F. No se aplica minúsculas,
/// colapso de espacios internos ni NFKC. Nunca se usa `trimmingCharacters(in: .whitespacesAndNewlines)`:
/// su conjunto no coincide con el del contrato.
public enum RecoveryPassphrase {
    /// `PASSPHRASE_TRIM` del contrato.
    public static let trimSet: Set<UInt32> = {
        var s: Set<UInt32> = [0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x0085, 0x00A0, 0x1680,
                              0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
        for v in 0x2000...0x200A { s.insert(UInt32(v)) }
        return s
    }()

    /// Cadena normalizada (NFC + recorte en los bordes), antes de codificar.
    public static func normalized(_ passphrase: String) -> String {
        let nfc = passphrase.precomposedStringWithCanonicalMapping
        var scalars = Array(nfc.unicodeScalars)
        while let first = scalars.first, trimSet.contains(first.value) { scalars.removeFirst() }
        while let last = scalars.last, trimSet.contains(last.value) { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Bytes UTF-8 exactos que entran en la derivación de clave.
    public static func bytes(_ passphrase: String) -> Data {
        Data(normalized(passphrase).utf8)
    }
}
