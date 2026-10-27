import Foundation

extension RecoveryPayload {
    /// Decodifica y valida contra §3.2 (obligatorios no anulables y patrones del esquema).
    public static func decode(_ data: Data) throws -> RecoveryPayload {
        let payload: RecoveryPayload
        do {
            payload = try JSONDecoder().decode(RecoveryPayload.self, from: data)
        } catch let error as DecodingError {
            throw RecoveryPayloadError.malformed(Self.describe(error))
        } catch {
            throw RecoveryPayloadError.malformed("JSON ilegible")
        }
        try payload.validate()
        return payload
    }

    /// JSON UTF-8 con claves ordenadas (forma canónica para sellar y comparar).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Ruta de la clave que falló, sin el valor (podría ser un secreto).
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            let base = path(context)
            return "falta \(base.isEmpty ? "" : base + ".")\(key.stringValue)"
        case .valueNotFound(_, let context):
            return "null no admitido en \(path(context))"
        case .typeMismatch(_, let context):
            return "tipo incorrecto en \(path(context))"
        case .dataCorrupted(let context):
            return "dato inválido en \(path(context))"
        @unknown default:
            return "error de decodificación"
        }
    }
}
