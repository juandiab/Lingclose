import Foundation

/// Aviso de que el diario cambió (alta, edición o borrado). Lo comparten Hoy, la pestaña Diario y los registros
/// rápidos para que cada pantalla recargue sus marcas y listas aunque el cambio venga de otra instancia de
/// `DiaryViewModel` (T-32). Difunde a todos los suscriptores; cada uno recibe como mucho el último aviso pendiente.
@MainActor
final class DiaryChangeFeed {
    /// `origin` identifica a quien guardó, para que no se recargue a sí mismo dos veces.
    struct Change: Sendable, Equatable {
        let origin: ObjectIdentifier?
    }

    private var continuations: [UUID: AsyncStream<Change>.Continuation] = [:]

    init() {}

    /// Suscriptores activos (pruebas).
    var subscriberCount: Int { continuations.count }

    /// Avisos a partir de ahora. Termina cuando se cancela la tarea que lo consume.
    func changes() -> AsyncStream<Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    /// Avisa a todos los suscriptores.
    func notify(from origin: AnyObject? = nil) {
        let change = Change(origin: origin.map(ObjectIdentifier.init))
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }
}
