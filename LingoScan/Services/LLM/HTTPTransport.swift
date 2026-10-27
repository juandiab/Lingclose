import Foundation

/// Envío HTTP inyectable: en la app `URLSessionTransport`, en pruebas respuestas grabadas.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
