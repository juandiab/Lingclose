import Foundation

/// Espera activa acotada para estados que cambian en tareas del coordinador.
func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

actor ValueBox<Value: Sendable> {
    private(set) var value: Value?
    func set(_ new: Value) { value = new }
}
