@preconcurrency import CoreBluetooth
import Foundation
import RoundWhiteDiscKit

/// `SensorLink` real sobre `SensorScanner`/`SensorSession`/`SensorSessionTransport` del fork.
///
/// - Central en modo segundo plano con identificador de restauración fijo. La app debe
///   crear esta instancia al arrancar para que iOS entregue `willRestoreState`.
/// - Ningún componente del fork recibe `eventLogger`: sus logs vuelcan PIN, kAuth y R1/R2 en hex.
actor RoundWhiteDiscSensorLink: SensorLink {
    static let restoreIdentifier = "com.otalvaro.lingoscan.ble"

    /// Orden de CCCD tras Phase 6 (`docs/PROTOCOLO_LINGO.md` §0.2).
    static let dataPlaneSubscriptionOrder: [CBUUID] = [
        LibreSensorGATT.Char.patchControl,
        LibreSensorGATT.Char.eventLog,
        LibreSensorGATT.Char.historicData,
        LibreSensorGATT.Char.clinicalData,
        LibreSensorGATT.Char.factoryData,
        LibreSensorGATT.Char.glucoseData,
        LibreSensorGATT.Char.patchStatus,
    ]

    private let scanner: SensorScanner
    private var session: SensorSession?
    private var transport: SensorSessionTransport?
    private var restored: [CBPeripheral] = []
    private var eventStream: AsyncStream<SensorLinkEvent>?
    private var eventContinuation: AsyncStream<SensorLinkEvent>.Continuation?
    private var pump: Task<Void, Never>?
    private var restorationListener: Task<Void, Never>?

    init(scanner: SensorScanner = SensorScanner(configuration: .background(restorationIdentifier: RoundWhiteDiscSensorLink.restoreIdentifier))) {
        self.scanner = scanner
    }

    /// Empieza a escuchar `restorationEvents()`. El escáner guarda los eventos previos
    /// a la suscripción, así que basta con llamarlo una vez al arrancar.
    func startRestorationListener() {
        guard restorationListener == nil else { return }
        let events = scanner.restorationEvents()
        restorationListener = Task { [weak self] in
            for await event in events {
                await self?.recordRestored(event)
            }
        }
    }

    func restoredPeripheralIDs() -> [UUID] {
        restored.map(\.identifier)
    }

    func connect(peripheralID: UUID?, timeout: Duration, scanWindow: Duration) async throws -> UUID {
        startRestorationListener()
        try await scanner.waitUntilReady()
        let seconds = timeout.timeInterval
        let newSession: SensorSession
        if let peripheralID, let peripheral = restored.first(where: { $0.identifier == peripheralID }),
           await scanner.state(of: peripheral) == .connected {
            newSession = try await scanner.resumeSession(for: peripheral)
        } else if let peripheralID,
                  let peripheral = await scanner.retrievePeripherals(withIdentifiers: [peripheralID]).first {
            newSession = try await scanner.connect(peripheral, timeout: seconds)
        } else {
            let found = try await scanFirst(window: scanWindow)
            newSession = try await scanner.connect(found.peripheral, timeout: seconds)
        }
        attach(newSession)
        let id = newSession.peripheral.identifier
        scanner.registerForConnectionEvents(peripheralIDs: [id])
        return id
    }

    func isConnected() async -> Bool {
        guard let session else { return false }
        return await scanner.state(of: session.peripheral) == .connected
    }

    func pairingTransport() throws -> any CommandPairingTransport {
        guard let transport else { throw SensorLinkError.notConnected }
        return transport
    }

    func enableDataPlaneNotifications(timeout: Duration) async throws {
        guard let session else { throw SensorLinkError.notConnected }
        let seconds = timeout.timeInterval
        // Secuencial y con off→on: iOS conserva el CCCD entre conexiones y un setNotify(true)
        // sobre una característica ya activa no escribe nada (`SensorSession.swift`).
        for uuid in Self.dataPlaneSubscriptionOrder {
            try await session.setNotify(false, for: uuid, timeout: seconds)
            try await session.setNotify(true, for: uuid, timeout: seconds)
        }
    }

    func events() -> AsyncStream<SensorLinkEvent> {
        if let eventStream { return eventStream }
        let (stream, continuation) = AsyncStream.makeStream(of: SensorLinkEvent.self)
        continuation.yield(.disconnected)
        continuation.finish()
        return stream
    }

    func writePatchControl(_ frame: Data) async throws {
        guard let session else { throw SensorLinkError.notConnected }
        try await session.writeRaw(frame, to: LibreSensorGATT.Char.patchControl)
    }

    func disconnect() {
        if let session { scanner.disconnect(session) }
        session = nil
        transport = nil
        eventContinuation?.yield(.disconnected)
        eventContinuation?.finish()
        eventContinuation = nil
        eventStream = nil
        pump?.cancel()
        pump = nil
    }

    // MARK: - Privado

    private func recordRestored(_ event: SensorRestorationEvent) {
        for peripheral in event.peripherals where !restored.contains(where: { $0.identifier == peripheral.identifier }) {
            restored.append(peripheral)
        }
    }

    private func attach(_ newSession: SensorSession) {
        pump?.cancel()
        eventContinuation?.finish()
        session = newSession
        transport = SensorSessionTransport(session: newSession)
        let (stream, continuation) = AsyncStream.makeStream(of: SensorLinkEvent.self)
        eventStream = stream
        eventContinuation = continuation
        let notifications = newSession.notifications()
        pump = Task {
            for await event in notifications {
                if let channel = DataPlaneChannel(uuidString: event.characteristic.uuidString) {
                    continuation.yield(.fragment(channel, event.fragment))
                }
            }
            continuation.yield(.disconnected)
            continuation.finish()
        }
    }

    /// Primer sensor que anuncia el servicio de datos durante `window`.
    /// Riesgo: con varios sensores cerca no hay forma de elegir por MAC (el fork no expone
    /// los datos de fabricante crudos); se usa el primero y el handshake falla si no es el nuestro.
    private func scanFirst(window: Duration) async throws -> DiscoveredSensor {
        let stream = scanner.startScan()
        defer { scanner.stopScan() }
        let found: DiscoveredSensor? = try await withThrowingTaskGroup(of: DiscoveredSensor?.self) { group in
            group.addTask {
                for await sensor in stream { return sensor }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: window)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let found else { throw SensorLinkError.sensorNotFound }
        return found
    }
}
