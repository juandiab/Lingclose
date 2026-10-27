import Foundation

/// Motivo exacto por el que un paquete `.lingoscan` no se importa (contrato §8.2–§8.3).
/// Cualquiera de ellos deja la base intacta.
public enum ArchiveValidationError: Error, Sendable, Hashable, LocalizedError {
    /// La ruta no es una carpeta `LingoScan-<tag>-<fecha>-<id8>.lingoscan`.
    case notAPackage(String)
    /// Carpeta `*.partial`: no es un paquete ni cuenta como copia (§3.1).
    case partialPackage
    case manifestMissing
    case manifestInvalid(String)
    case unsupportedContractVersion(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// `snapshot.complete != true` (§4).
    case snapshotIncomplete
    /// El nombre de la carpeta no coincide con `archive_id` / `created_at_utc` del manifest.
    case nameMismatch(String)
    /// Un archivo obligatorio no figura en `files[]`.
    case mandatoryFileNotListed(String)
    case invalidFileName(String)
    case fileMissing(String)
    case sizeMismatch(file: String, expected: Int, actual: Int)
    case hashMismatch(file: String, expected: String, actual: String)
    /// Codificación, BOM o saltos de línea no permitidos en un archivo entero.
    case invalidFile(file: String, detail: String)
    /// Una línea NDJSON (o el JSON de `sessions.json`) no cumple el esquema (§8.3).
    case invalidLine(file: String, line: Int, detail: String)
    /// Regla entre registros: duplicados, referencias huérfanas, hex inválido…
    case invalidRecord(file: String, detail: String)
    /// Clave prohibida en una sesión (§1.7): secretos que solo viven en el archivo de recuperación.
    case forbiddenSessionKey(String)
    /// Procedencia sintética incoherente (§4, C6 y ajuste de Astra: lectura real en sesión sintética).
    case syntheticInconsistency(String)
    case countMismatch(String)

    /// Identificador estable para registros y pruebas.
    public var code: String {
        switch self {
        case .notAPackage: "not_a_package"
        case .partialPackage: "partial_package"
        case .manifestMissing: "manifest_missing"
        case .manifestInvalid: "manifest_invalid"
        case .unsupportedContractVersion: "unsupported_contract_version"
        case .unsupportedSchemaVersion: "unsupported_schema_version"
        case .snapshotIncomplete: "snapshot_incomplete"
        case .nameMismatch: "name_mismatch"
        case .mandatoryFileNotListed: "mandatory_file_not_listed"
        case .invalidFileName: "invalid_file_name"
        case .fileMissing: "file_missing"
        case .sizeMismatch: "size_mismatch"
        case .hashMismatch: "hash_mismatch"
        case .invalidFile: "invalid_file"
        case .invalidLine: "invalid_line"
        case .invalidRecord: "invalid_record"
        case .forbiddenSessionKey: "forbidden_session_key"
        case .syntheticInconsistency: "synthetic_inconsistency"
        case .countMismatch: "count_mismatch"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notAPackage(let s): "No es un paquete LingoScan: \(s)"
        case .partialPackage: "Carpeta .partial: exportación sin terminar; se ignora"
        case .manifestMissing: "Falta manifest.json: sin manifest no hay paquete"
        case .manifestInvalid(let s): "manifest.json inválido: \(s)"
        case .unsupportedContractVersion(let v): "contract_version \(v) no compatible (se acepta major 1)"
        case .unsupportedSchemaVersion(let f, let s): "schema_version \(f) es mayor que el soportado (\(s))"
        case .snapshotIncomplete: "snapshot.complete no es true: el paquete está incompleto"
        case .nameMismatch(let s): "El nombre de la carpeta no coincide con el manifest: \(s)"
        case .mandatoryFileNotListed(let f): "El archivo obligatorio \(f) no figura en files[]"
        case .invalidFileName(let f): "Nombre de archivo no permitido en files[]: \(f)"
        case .fileMissing(let f): "Archivo listado pero ausente: \(f)"
        case .sizeMismatch(let f, let e, let a): "\(f): bytes del manifest \(e), reales \(a)"
        case .hashMismatch(let f, _, _): "\(f): el SHA-256 no coincide con el manifest"
        case .invalidFile(let f, let d): "\(f): \(d)"
        case .invalidLine(let f, let l, let d): "\(f), línea \(l): \(d)"
        case .invalidRecord(let f, let d): "\(f): \(d)"
        case .forbiddenSessionKey(let k): "Una sesión contiene la clave prohibida \(k)"
        case .syntheticInconsistency(let d): "Procedencia sintética incoherente: \(d)"
        case .countMismatch(let d): "Conteos incoherentes: \(d)"
        }
    }
}
