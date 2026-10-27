import Foundation
import LingoCore
import RoundWhiteDiscKit

/// Evidencia de un handshake interrumpido, ya redactada para estado y `event_log`.
/// Un corte es evidencia, no un diagnóstico: nunca se presenta como credencial rechazada.
struct AuthInterruptionEvidence: Sendable, Equatable {
    let lastCommandSent: UInt8?
    /// `Redactor.hex` de lo último recibido (respuestas de 1 B completas; blobs recortados).
    let lastBytesRedacted: String?
    let elapsedSeconds: Double
    /// Error de transporte que cortó el handshake (sin bytes de claves).
    let underlying: String

    init(lastCommandSent: UInt8?, lastBytesRedacted: String?, elapsedSeconds: Double, underlying: String) {
        self.lastCommandSent = lastCommandSent
        self.lastBytesRedacted = lastBytesRedacted
        self.elapsedSeconds = elapsedSeconds
        self.underlying = String(underlying.prefix(160))
    }

    init(_ evidence: AuthEvidence) {
        self.init(
            lastCommandSent: evidence.lastCommandSent,
            lastBytesRedacted: evidence.lastBytesReceived.map(Redactor.hex),
            elapsedSeconds: evidence.elapsed,
            underlying: evidence.underlying
        )
    }

    var lastCommandText: String {
        guard let lastCommandSent else { return "ninguno" }
        return "0x" + Data([lastCommandSent]).lowercaseHex
    }
}
