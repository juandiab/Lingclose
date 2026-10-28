import Foundation
import Observation

/// Estado de la hoja "Sugerir rango": calculando → lista (con la sugerencia) o fallida (con el motivo). La
/// aceptación la hace la hoja llamando a `onAccept` con los valores ya ajustados a lo editable en Ajustes.
@MainActor
@Observable
final class RangeSuggestionViewModel {
    enum Phase: Equatable {
        case loading
        case ready(RangeSuggestion)
        case failed(String)
    }

    private(set) var phase: Phase = .loading

    @ObservationIgnored private let suggester: any RangeSuggesting
    @ObservationIgnored private var task: Task<Void, Never>?

    init(suggester: any RangeSuggesting) {
        self.suggester = suggester
    }

    var suggestion: RangeSuggestion? {
        if case .ready(let suggestion) = phase { return suggestion }
        return nil
    }

    var canAccept: Bool { suggestion != nil }

    /// Valores que se aplicarán al aceptar: los de la sugerencia, acotados a lo que Ajustes permite editar.
    var applied: (low: Int, high: Int)? {
        suggestion.map { ReferenceLines.clampedForSettings(low: $0.low, high: $0.high) }
    }

    var isAdjustedForSettings: Bool {
        guard let suggestion, let applied else { return false }
        return applied.low != suggestion.low || applied.high != suggestion.high
    }

    /// Una sola construcción por hoja, en una sola `Task`, para que `cancel()` llegue hasta `suggest()`
    /// (y, con ella, a la llamada al proveedor). Nada se repite solo.
    func load() async {
        guard task == nil else { return }
        let task = Task { await compute() }
        self.task = task
        await task.value
    }

    /// "Descartar" o cerrar la hoja mientras calcula: corta la petición en curso sin mostrar error.
    func cancel() {
        task?.cancel()
    }

    private func compute() async {
        do {
            let suggestion = try await suggester.suggest()
            guard !Task.isCancelled else { return }
            phase = .ready(suggestion)
        } catch is CancellationError {
            // Descartada por el usuario: no es un fallo.
        } catch let error as RangeSuggestionError {
            phase = .failed(error.description)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
