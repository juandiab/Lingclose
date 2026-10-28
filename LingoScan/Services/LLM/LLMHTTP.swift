import Foundation
import LingoCore

/// Utilidades HTTP comunes: construir peticiones, enviar una sola vez, mapear errores (`docs/T-21.md`
/// §4) y leer JSON. Los mensajes del proveedor se recortan y se les borra la clave.
enum LLMHTTP {
    static let timeout: TimeInterval = 60
    static let maxMessageLength = 200

    static func request(url: URL, method: String = "GET", headers: [String: String], body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
            } catch {
                throw LLMError.invalidResponse(String(localized: "no se pudo preparar la petición"))
            }
        }
        return request
    }

    /// Envía una vez (sin reintentos) y devuelve el cuerpo de una respuesta 2xx; si no, el `LLMError`.
    static func perform(_ request: URLRequest, provider: LLMProviderID, operation: String, apiKey: String,
                        transport: any HTTPTransport, log: any LLMLogSink) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as LLMError {
            throw error
        } catch let error as URLError {
            log.log("\(provider.rawValue) \(operation): error de red \(error.code.rawValue)")
            throw LLMError.network(String(localized: "código \(error.code.rawValue)"))
        } catch {
            log.log("\(provider.rawValue) \(operation): error de red")
            throw LLMError.network(String(describing: type(of: error)))
        }
        log.log("\(provider.rawValue) \(operation): HTTP \(response.statusCode), \(data.count) bytes")
        guard (200..<300).contains(response.statusCode) else {
            throw mapError(status: response.statusCode, data: data, apiKey: apiKey)
        }
        return data
    }

    /// 401/403 → `unauthorized`; 402 o mensaje de saldo → `quotaExceeded`; 429 → `rateLimited`.
    static func mapError(status: Int, data: Data, apiKey: String) -> LLMError {
        let (message, code) = errorDetails(data, apiKey: apiKey)
        let haystack = (message + " " + code).lowercased()
        // Gemini responde 400 a una clave inválida; el texto solo se mira en 400, nunca en 5xx.
        let keyMarkers = ["api key not valid", "invalid api key", "incorrect api key", "authentication_error", "invalid_api_key"]
        if status == 401 || status == 403 || (status == 400 && keyMarkers.contains(where: haystack.contains)) {
            return .unauthorized
        }
        let quotaMarkers = ["insufficient_quota", "insufficient balance", "insufficient_balance", "credit balance",
                            "billing_error", "billing", "insufficient credits", "out of credits"]
        if status == 402 || (status < 500 && quotaMarkers.contains(where: haystack.contains)) { return .quotaExceeded }
        if status == 429 { return .rateLimited }
        return .server(status: status, message: message)
    }

    /// Mensaje y código de error del proveedor (`error.message`, `error.type`/`code`/`status`),
    /// recortados y sin la clave. Si el cuerpo no es JSON, no se copia.
    static func errorDetails(_ data: Data, apiKey: String) -> (message: String, code: String) {
        var message = String(localized: "sin detalle")
        var code = ""
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let m = error["message"] as? String { message = m }
                code = [error["type"], error["code"], error["status"]].compactMap { $0.map { "\($0)" } }.joined(separator: " ")
            } else if let m = object["error"] as? String {
                message = m
            } else if let m = object["message"] as? String {
                message = m
            }
        }
        return (sanitize(message, apiKey: apiKey), sanitize(code, apiKey: apiKey))
    }

    static func sanitize(_ text: String, apiKey: String) -> String {
        var text = text
        if !apiKey.isEmpty { text = text.replacingOccurrences(of: apiKey, with: "•••") }
        text = text.replacingOccurrences(of: "\n", with: " ")
        if text.count > maxMessageLength { text = String(text.prefix(maxMessageLength)) + "…" }
        return text
    }

    static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(String(localized: "el proveedor no devolvió JSON"))
        }
        return object
    }

    static func parseAnalysis(text: String) throws -> FoodAnalysis {
        do {
            return try FoodAnalysisParser.parse(text: text)
        } catch let error as FoodAnalysisParserError {
            throw LLMError.invalidResponse(String(describing: error))
        }
    }

    static func parseAnalysis(object: [String: Any]) throws -> FoodAnalysis {
        do {
            return try FoodAnalysisParser.parse(object: object)
        } catch let error as FoodAnalysisParserError {
            throw LLMError.invalidResponse(String(describing: error))
        }
    }

    /// Comprobaciones previas comunes a todos los proveedores, antes de gastar una petición.
    static func validate(_ request: FoodAnalysisRequest, model: LLMModel, provider: LLMProviderID) throws {
        guard model.provider == provider else {
            throw LLMError.invalidResponse(String(localized: "el modelo es de otro proveedor"))
        }
        if request.hasImage && model.imageSupport != .confirmed { throw LLMError.modelLacksVision }
        guard request.hasImage || request.trimmedDescription != nil else {
            throw LLMError.invalidResponse(String(localized: "no hay foto ni descripción que analizar"))
        }
    }

    /// Comprobación previa de "Sugerir rango": solo texto, así que basta con que el modelo sea del proveedor.
    static func validate(model: LLMModel, provider: LLMProviderID) throws {
        guard model.provider == provider else {
            throw LLMError.invalidResponse(String(localized: "el modelo es de otro proveedor"))
        }
    }

    /// Precio por token (cadena, USD) → USD por millón de tokens, redondeado a 6 decimales.
    static func perMillion(_ perToken: Any?) -> Double? {
        let value: Double?
        switch perToken {
        case let s as String: value = Double(s)
        case let n as NSNumber: value = n.doubleValue
        default: value = nil
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return (value * 1_000_000 * 1_000_000).rounded() / 1_000_000
    }
}
