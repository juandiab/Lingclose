import Foundation

/// Transporte real. Sesión efímera: sin caché en disco ni cookies, para que ni la foto ni la clave
/// queden guardadas por `URLSession`.
struct URLSessionTransport: HTTPTransport {
    static let ephemeralSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 180
        return URLSession(configuration: configuration)
    }()

    let session: URLSession

    init(session: URLSession = URLSessionTransport.ephemeralSession) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
