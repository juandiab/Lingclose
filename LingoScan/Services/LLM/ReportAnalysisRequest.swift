import CryptoKit
import Foundation
import LingoCore

/// Lo único que sale del teléfono al analizar un reporte (T-27d): el `ReportSnapshot` compacto (números, series
/// remuestreadas, hora/carbohidratos/duración de comidas y ejercicios) y la lista de reportes con datos suficientes.
/// Sin nombres, notas, fotos, ids, seriales ni la zona horaria por nombre (el snapshot ya viene así). `locale` solo
/// elige el idioma de la respuesta.
struct ReportAnalysisRequest: Sendable, Equatable {
    /// Reportes con datos suficientes: una sección cada uno.
    var topicsWithData: [ReportAnalysisTopic]
    var topicsWithoutData: [ReportAnalysisTopic]
    /// JSON del snapshot compacto (claves ordenadas: mismos datos, mismos bytes).
    var snapshotJSON: String
    var periodDays: Int
    var locale: String

    init(bundle: ReportBundle, locale: String, maxBytes: Int = ReportSnapshot.defaultMaxBytes) throws {
        let snapshot = bundle.snapshot.compact(maxBytes: maxBytes)
        guard let json = String(data: try snapshot.jsonData(), encoding: .utf8) else {
            throw LLMError.invalidResponse(String(localized: "reports.analysis.error.encode", defaultValue: "no se pudo preparar el reporte"))
        }
        snapshotJSON = json
        topicsWithData = ReportAnalysisTopic.allCases.filter { $0.hasEnoughData(in: bundle) }
        topicsWithoutData = ReportAnalysisTopic.allCases.filter { !$0.hasEnoughData(in: bundle) }
        periodDays = snapshot.period.days
        self.locale = locale
    }

    /// Mensaje del usuario: qué reportes tienen datos y el JSON del snapshot.
    var userText: String {
        let with = topicsWithData.map(\.rawValue).joined(separator: ", ")
        let without = topicsWithoutData.map(\.rawValue).joined(separator: ", ")
        return """
        Reporte de glucosa de \(periodDays) días (sin lecturas individuales identificables ni texto libre).
        Reportes con datos suficientes (una sección cada uno): \(with.isEmpty ? "ninguno" : with)
        Reportes sin datos suficientes (no escribas sección): \(without.isEmpty ? "ninguno" : without)
        Datos (JSON):
        \(snapshotJSON)
        """
    }

    /// Tamaño del mensaje enviado, en bytes.
    var payloadBytes: Int { userText.utf8.count }

    /// SHA-256 hexadecimal del mensaje de usuario, que contiene el JSON del snapshot: sirve para reconocer
    /// peticiones repetidas sin guardar los datos. Estable: mismo reporte, mismo hash.
    var sha256: String {
        SHA256.hash(data: Data(userText.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
