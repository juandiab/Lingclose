import Foundation

extension Duration {
    /// Segundos como `TimeInterval`, para las API del fork que aún reciben segundos.
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
