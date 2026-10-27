import Foundation

/// NDJSON del contrato §2: un objeto JSON por línea, UTF-8 sin BOM, saltos `\n`.
enum NDJSON {
    static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted] : [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Una línea por elemento, cada una terminada en `\n`. Claves ordenadas para que dos exportaciones
    /// del mismo estado den los mismos bytes.
    static func encode(_ values: [JSONValue]) throws -> Data {
        let encoder = makeEncoder()
        var out = Data()
        for v in values {
            out.append(try encoder.encode(v))
            out.append(0x0A)
        }
        return out
    }

    /// Separa un archivo NDJSON en líneas (número desde 1). Rechaza BOM, `\r` y líneas vacías (§2).
    static func lines(of data: Data, file: String) throws -> [(number: Int, bytes: Data)] {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            throw ArchiveValidationError.invalidFile(file: file, detail: "lleva BOM (UTF-8 sin BOM)")
        }
        if data.contains(0x0D) {
            throw ArchiveValidationError.invalidFile(file: file, detail: "contiene retorno de carro (solo \\n)")
        }
        var parts = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if let last = parts.last, last.isEmpty { parts.removeLast() }
        var out: [(Int, Data)] = []
        out.reserveCapacity(parts.count)
        for (i, p) in parts.enumerated() {
            let n = i + 1
            if p.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
                throw ArchiveValidationError.invalidLine(file: file, line: n, detail: "línea vacía dentro del NDJSON")
            }
            out.append((n, Data(p)))
        }
        return out
    }
}

/// `readings.csv` (contrato §5.6): derivado para humanos, nunca se importa.
public enum CSVWriter {
    public static let header = "record_id,session_id,life_count,measured_at_utc,measured_at_local,tz,origin,"
        + "value_mgdl,eligible,exclusion_reason,trend,rate_centi,quality_flag"

    /// Cabecera + una fila por lectura, `\n` al final de cada línea.
    public static func file(for readings: [GlucoseReading]) -> Data {
        var text = header + "\n"
        text.reserveCapacity(readings.count * 190)
        for r in readings { text += row(r) + "\n" }
        return Data(text.utf8)
    }

    public static func row(_ r: GlucoseReading) -> String {
        [
            r.recordID, r.sessionID, String(r.lifeCount), r.measuredAt.rfc3339,
            localTime(r.measuredAt, timeZoneIdentifier: r.tzAtCapture), r.tzAtCapture, r.origin.rawValue,
            r.value.map(String.init) ?? "", r.eligibility.isEligible ? "true" : "false",
            r.eligibility.reason?.rawValue ?? "", r.raw.trend.map(String.init) ?? "",
            r.raw.rateCenti.map(String.init) ?? "", r.raw.qualityFlag ? "true" : "false",
        ].map(escape).joined(separator: ",")
    }

    /// Comillas dobles solo cuando haga falta.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 3339 con el desfase de la zona IANA en ese instante (`2026-10-27T07:00:59-05:00`).
    /// Una zona desconocida se escribe con desfase `+00:00`.
    public static func localTime(_ instant: UTCInstant, timeZoneIdentifier: String) -> String {
        let offset = TimeZone(identifier: timeZoneIdentifier)?.secondsFromGMT(for: instant.date) ?? 0
        let shifted = instant.adding(seconds: Int64(offset)).rfc3339.dropLast()
        let a = abs(offset)
        let hh = String(a / 3600), mm = String((a % 3600) / 60)
        let sign = offset < 0 ? "-" : "+"
        return shifted + sign + (hh.count < 2 ? "0" + hh : hh) + ":" + (mm.count < 2 ? "0" + mm : mm)
    }
}
