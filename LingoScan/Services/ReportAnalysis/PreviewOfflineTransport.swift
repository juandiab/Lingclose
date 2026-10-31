import Foundation

/// Transporte sin red para la previsualización del análisis: toda petición falla como "sin conexión" y nunca sale nada.
struct PreviewOfflineTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
