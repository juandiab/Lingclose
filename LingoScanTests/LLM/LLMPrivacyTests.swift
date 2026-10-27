import Foundation
import Testing
import LingoCore
@testable import LingoScan

/// Solo salen la foto y la descripción; la clave nunca aparece en errores, logs ni cuerpos.
struct LLMPrivacyTests {
    static let forbiddenMarkers = ["glucos", "glucose", "mg/dl", "mmol", "healthkit", "salud", "workout", "entrenamiento",
                                   "sensor", "lingo", "heart", "insulin"]

    /// Todas las cadenas de un JSON (claves y valores), en minúsculas.
    private func strings(in value: Any) -> [String] {
        switch value {
        case let s as String: [s]
        case let d as [String: Any]: d.flatMap { [$0.key] + strings(in: $0.value) }
        case let a as [Any]: a.flatMap { strings(in: $0) }
        default: []
        }
    }

    @Test(arguments: LLMProviderID.allCases)
    func requestCarriesOnlyPhotoAndDescription(provider: LLMProviderID) async throws {
        let transport = FixtureTransport(fixture: "\(provider.rawValue)-food")
        _ = try await LLMFixtures.provider(provider, transport: transport)
            .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
        let request = try #require(transport.requests.first)
        let body = try #require(request.httpBody)
        let bodyText = try #require(String(data: body, encoding: .utf8))
        let json = try JSONSerialization.jsonObject(with: body)

        // Lo que sí sale.
        #expect(bodyText.contains(LLMFixtures.foodDescription))
        let rawStrings = strings(in: json)
        if provider != .deepseek {
            let base64 = LLMFixtures.fakeJPEG.base64EncodedString()
            #expect(rawStrings.contains { $0.hasSuffix(base64) })
        }
        // Lo que nunca sale: ningún dato de glucosa, Salud ni entrenamientos, ni la clave.
        let allStrings = rawStrings.map { $0.lowercased() }
        for marker in Self.forbiddenMarkers {
            #expect(!allStrings.contains { $0.contains(marker) }, "marcador \(marker) en la petición de \(provider)")
        }
        #expect(!bodyText.contains(LLMFixtures.testKey))
        #expect(!(request.url?.absoluteString.contains(LLMFixtures.testKey) ?? true), "la clave no va en la URL")
        #expect(request.httpMethod == "POST")
    }

    @Test(arguments: LLMProviderID.allCases)
    func keyNeverAppearsInErrorsOrLogs(provider: LLMProviderID) async throws {
        let cases: [(Int, String)] = [(401, "401"), (429, "429"), (500, "500"), (200, "truncated"), (200, "broken")]
        let log = RecordingLLMLogSink()
        var descriptions: [String] = []
        for (status, name) in cases {
            let transport = FixtureTransport(status: status, fixture: "\(provider.rawValue)-\(name)")
            do {
                _ = try await LLMFixtures.provider(provider, transport: transport, log: log)
                    .analyze(LLMFixtures.request(for: provider), model: LLMFixtures.model(for: provider), apiKey: LLMFixtures.testKey)
                Issue.record("\(provider)-\(name) debía fallar")
            } catch {
                descriptions.append(String(describing: error))
                descriptions.append(error.localizedDescription)
            }
        }
        // También el catálogo y el error de red.
        do {
            _ = try await LLMFixtures.provider(provider, transport: FixtureTransport([]), log: log).listModels(apiKey: LLMFixtures.testKey)
        } catch {
            descriptions.append(String(describing: error))
        }
        #expect(descriptions.count == 11)
        for text in descriptions + log.messages {
            #expect(!text.contains(LLMFixtures.testKey), "fuga de clave: \(text)")
            #expect(!text.contains(LLMFixtures.foodDescription), "la descripción no va a logs ni errores")
        }
        #expect(!log.messages.isEmpty)
    }

    @Test func serverMessageEchoingTheKeyIsRedacted() async throws {
        let transport = FixtureTransport(status: 500, fixture: "openai-500")
        do {
            _ = try await LLMFixtures.provider(.openai, transport: transport)
                .analyze(LLMFixtures.request(for: .openai), model: LLMFixtures.model(for: .openai), apiKey: LLMFixtures.testKey)
            Issue.record("debía fallar")
        } catch let error as LLMError {
            guard case .server(500, let message) = error else { Issue.record("esperaba server(500), llegó \(error)"); return }
            #expect(message.contains("•••"))
            #expect(!message.contains(LLMFixtures.testKey))
        }
    }

    @Test func everyErrorHasASpanishDescriptionWithoutSecrets() {
        let errors: [LLMError] = [.unauthorized, .quotaExceeded, .rateLimited, .refused("x"), .incomplete("y"),
                                  .modelLacksVision, .network("z"), .server(status: 503, message: "m"), .invalidResponse("w")]
        for error in errors {
            #expect(!error.description.isEmpty)
            #expect(error.localizedDescription == error.description)
        }
        #expect(LLMError.unauthorized.description.contains("clave"))
    }
}
