import CryptoKit
import Foundation
import LingoCore

/// Lo único que sale del teléfono al analizar un reporte (T-27d, T-33): el `ReportSnapshot` compacto (números, series
/// remuestreadas, hora/carbohidratos/duración de comidas y ejercicios), la lista de reportes con datos suficientes y,
/// solo si el usuario lo encendió, el contexto opcional (`ReportAnalysisContext`: comidas con nombre, sueño, pasos,
/// perfil) en un bloque aparte. Sin notas, fotos, ids, seriales ni la zona horaria por nombre. `locale` solo elige el
/// idioma de la respuesta.
struct ReportAnalysisRequest: Sendable, Equatable {
    /// Reportes con datos suficientes: una sección cada uno.
    var topicsWithData: [ReportAnalysisTopic]
    var topicsWithoutData: [ReportAnalysisTopic]
    /// JSON del snapshot compacto (claves ordenadas: mismos datos, mismos bytes).
    var snapshotJSON: String
    var periodDays: Int
    var locale: String
    /// Contexto opcional; `nil` con los tres interruptores apagados o sin nada que enviar.
    var context: ReportAnalysisContext?
    /// JSON del contexto (claves ordenadas); `nil` sin contexto.
    var contextJSON: String?

    init(bundle: ReportBundle, locale: String, maxBytes: Int = ReportSnapshot.defaultMaxBytes) throws {
        try self.init(bundle: bundle, snapshot: bundle.snapshot.compact(maxBytes: maxBytes), locale: locale, context: nil)
    }

    /// Con el snapshot ya compactado (el mismo con el que se armó el contexto).
    init(bundle: ReportBundle, snapshot: ReportSnapshot, locale: String, context: ReportAnalysisContext?) throws {
        guard let json = String(data: try snapshot.jsonData(), encoding: .utf8) else {
            throw LLMError.invalidResponse(String(localized: "reports.analysis.error.encode", defaultValue: "no se pudo preparar el reporte"))
        }
        snapshotJSON = json
        topicsWithData = ReportAnalysisTopic.allCases.filter { $0.hasEnoughData(in: bundle) }
        topicsWithoutData = ReportAnalysisTopic.allCases.filter { !$0.hasEnoughData(in: bundle) }
        periodDays = snapshot.period.days
        self.locale = locale
        let context = context.flatMap { $0.isEmpty ? nil : $0 }
        self.context = context
        contextJSON = try context.map { context in
            guard let text = String(data: try context.jsonData(), encoding: .utf8) else {
                throw LLMError.invalidResponse(String(localized: "reports.analysis.error.encode", defaultValue: "no se pudo preparar el reporte"))
            }
            return text
        }
    }

    /// Mensaje del usuario: qué reportes tienen datos, qué contexto opcional va, el JSON del snapshot y, si hay, el del
    /// contexto. Con los tres interruptores apagados es el mensaje de T-27d más la línea "Contexto opcional incluido:
    /// ninguno".
    var userText: String {
        let with = topicsWithData.map(\.rawValue).joined(separator: ", ")
        let without = topicsWithoutData.map(\.rawValue).joined(separator: ", ")
        let blocks = context?.includedBlocks ?? []
        let privacy = context?.meals == nil
            ? "sin lecturas individuales identificables ni texto libre"
            : "sin lecturas individuales identificables; los nombres de comidas van en el contexto opcional"
        var text = """
        Reporte de glucosa de \(periodDays) días (\(privacy)).
        Reportes con datos suficientes (una sección cada uno): \(with.isEmpty ? "ninguno" : with)
        Reportes sin datos suficientes (no escribas sección): \(without.isEmpty ? "ninguno" : without)
        Contexto opcional incluido: \(blocks.isEmpty ? "ninguno" : blocks.joined(separator: ", "))
        Datos (JSON):
        \(snapshotJSON)
        """
        if let contextJSON {
            text += "\nContexto opcional (JSON):\n\(contextJSON)"
        }
        return text
    }

    /// Tamaño del mensaje enviado, en bytes (snapshot y contexto).
    var payloadBytes: Int { userText.utf8.count }

    /// Bytes del bloque de contexto (0 sin contexto).
    var contextBytes: Int { contextJSON?.utf8.count ?? 0 }

    /// SHA-256 hexadecimal del mensaje de usuario completo (snapshot y contexto): sirve para reconocer peticiones
    /// repetidas sin guardar los datos. Estable: mismo reporte y mismo contexto, mismo hash.
    var sha256: String {
        SHA256.hash(data: Data(userText.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
