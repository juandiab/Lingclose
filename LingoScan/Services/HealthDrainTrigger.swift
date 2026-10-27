import Foundation

/// Drenado automático a Health: llama a `HealthExporter.drain()` cuando el coordinador inserta una lectura
/// nueva (con un debounce de 30 s) y al volver la app a primer plano.
///
/// El debounce es "de cola": cada aviso reinicia la espera, así que con una lectura por minuto el drenado
/// ocurre unos 30 s después de cada lectura; si llegan avisos más seguidos, se agrupan en un solo drenado.
/// `HealthExporter` ignora una llamada si ya hay un drenado en curso y respeta el modo "en pausa".
@MainActor
final class HealthDrainTrigger {
    /// Instancia activa (una por proceso); `TodayView` la avisa al volver a primer plano.
    private(set) static var current: HealthDrainTrigger?

    static let defaultDebounce: Duration = .seconds(30)

    private let drain: @Sendable () async -> Void
    private let debounce: Duration
    private var watchTask: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?

    /// - Parameters:
    ///   - changes: aviso por cada lectura nueva (la misma señal con la que `LiveTodayDataSource` refresca Hoy).
    ///   - drain: acción de drenado; en producción `exporter.drain()`.
    init(
        changes: AsyncStream<Void>,
        debounce: Duration = HealthDrainTrigger.defaultDebounce,
        drain: @escaping @Sendable () async -> Void
    ) {
        self.drain = drain
        self.debounce = debounce
        watchTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.scheduleDebouncedDrain()
            }
        }
    }

    isolated deinit {
        watchTask?.cancel()
        pendingTask?.cancel()
    }

    /// Registra esta instancia como la activa del proceso.
    func install() {
        Self.current = self
    }

    /// Llamar con `scenePhase == .active`: drena sin esperar.
    func sceneDidBecomeActive() {
        pendingTask?.cancel()
        pendingTask = Task { [drain] in await drain() }
    }

    private func scheduleDebouncedDrain() {
        pendingTask?.cancel()
        let drain = drain
        let debounce = debounce
        pendingTask = Task {
            do { try await Task.sleep(for: debounce) } catch { return }
            await drain()
        }
    }
}
