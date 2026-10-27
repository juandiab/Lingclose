import Foundation

/// Reloj inyectable del coordinador (staleness, esperas entre reintentos).
protocol SessionClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}
