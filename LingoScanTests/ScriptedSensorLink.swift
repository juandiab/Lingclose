import Foundation
import RoundWhiteDiscKit
@testable import LingoScan

/// `SensorLink` guionado: el handshake lo responde `SyntheticLingoSensor` y el test inyecta
/// las notificaciones del plano de datos con `emit`.
actor ScriptedSensorLink: SensorLink {
    let sensor: SyntheticLingoSensor
    nonisolated let peripheralID = UUID()
    private let restored: [UUID]
    private(set) var connectRequests: [UUID?] = []
    private(set) var subscribeCount = 0
    private(set) var patchControlWrites: [Data] = []
    private var connected = false
    private var continuation: AsyncStream<SensorLinkEvent>.Continuation?
    private var stream: AsyncStream<SensorLinkEvent>?
    private var onConnect: (@Sendable () async -> Void)?

    init(sensor: SyntheticLingoSensor, restored: [UUID] = []) {
        self.sensor = sensor
        self.restored = restored
    }

    var connectCount: Int { connectRequests.count }

    func setOnConnect(_ probe: @escaping @Sendable () async -> Void) { onConnect = probe }

    func emit(_ event: SensorLinkEvent) { continuation?.yield(event) }

    /// Cierra el enlace desde el lado del sensor.
    func dropLink() { disconnect() }

    func restoredPeripheralIDs() -> [UUID] { restored }

    func connect(peripheralID: UUID?, timeout: Duration, scanWindow: Duration) async throws -> UUID {
        connectRequests.append(peripheralID)
        await onConnect?()
        let (newStream, newContinuation) = AsyncStream.makeStream(of: SensorLinkEvent.self)
        stream = newStream
        continuation = newContinuation
        connected = true
        return self.peripheralID
    }

    func isConnected() -> Bool { connected }

    func pairingTransport() throws -> any CommandPairingTransport {
        guard connected else { throw SensorLinkError.notConnected }
        return sensor
    }

    func enableDataPlaneNotifications(timeout: Duration) {
        subscribeCount += 1
    }

    func events() -> AsyncStream<SensorLinkEvent> {
        if let stream { return stream }
        let (finished, c) = AsyncStream.makeStream(of: SensorLinkEvent.self)
        c.finish()
        return finished
    }

    func writePatchControl(_ frame: Data) {
        patchControlWrites.append(frame)
    }

    func disconnect() {
        connected = false
        continuation?.yield(.disconnected)
        continuation?.finish()
        continuation = nil
        stream = nil
    }
}
