import Synchronization

/// Generador de Receiver IDs para tests: devuelve 0x0100_0001, 0x0100_0002, … y cuenta las llamadas.
final class CountingReceiverIDs: Sendable {
    private let issued = Mutex<[UInt32]>([])

    var values: [UInt32] { issued.withLock { $0 } }

    func next() -> UInt32 {
        issued.withLock { list in
            let value = 0x0100_0001 + UInt32(list.count)
            list.append(value)
            return value
        }
    }
}
