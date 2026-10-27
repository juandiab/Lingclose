import Synchronization
@testable import LingoScan

/// Guarda los mensajes de log para comprobar que nunca contienen la clave ni datos del usuario.
final class RecordingLLMLogSink: LLMLogSink {
    private let lines = Mutex<[String]>([])

    var messages: [String] { lines.withLock { $0 } }

    func log(_ message: String) {
        lines.withLock { $0.append(message) }
    }
}
