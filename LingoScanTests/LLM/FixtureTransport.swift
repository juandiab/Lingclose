import Foundation
import Synchronization
@testable import LingoScan

/// Transporte de pruebas: devuelve respuestas grabadas en orden y registra cada petición. Nunca toca
/// la red. Si se agotan las respuestas, falla con `URLError(.notConnectedToInternet)`.
final class FixtureTransport: HTTPTransport {
    struct Reply: Sendable {
        var status: Int
        var body: Data
    }

    private struct State {
        var replies: [Reply]
        var requests: [URLRequest] = []
    }

    private let state: Mutex<State>

    init(_ replies: [Reply]) {
        state = Mutex(State(replies: replies))
    }

    /// Una respuesta con el cuerpo de `Fixtures/LLM/<name>.json`.
    convenience init(status: Int = 200, fixture name: String) {
        self.init([Reply(status: status, body: LLMFixtures.data(name))])
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = state.withLock { state in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        return (reply.body, response)
    }
}
