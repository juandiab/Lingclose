import Foundation
import os

/// Aviso de cambio en Salud. Lleva el completion handler de `HKObserverQuery`: hay que llamar a `acknowledge()`
/// cuando termine la importación (en segundo plano, iOS espera esa señal). Se llama como mucho una vez; si nadie
/// lo llama, se llama al liberarse.
final class WorkoutChangeNotice: Sendable {
    private let completion: OSAllocatedUnfairLock<(@Sendable () -> Void)?>

    init(completion: @escaping @Sendable () -> Void = {}) {
        self.completion = OSAllocatedUnfairLock(initialState: completion)
    }

    func acknowledge() {
        let handler = completion.withLock { value -> (@Sendable () -> Void)? in
            defer { value = nil }
            return value
        }
        handler?()
    }

    deinit { acknowledge() }
}
