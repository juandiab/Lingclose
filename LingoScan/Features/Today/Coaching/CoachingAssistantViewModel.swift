import Foundation
import LingoCore
import Observation

/// Estado de la hoja del asistente (T-25): una sola petición al abrirla (sin reintentos cobrables), respuesta o
/// error claro, y "Guardar como nota" en el diario.
@MainActor
@Observable
final class CoachingAssistantViewModel {
    enum Phase: Equatable {
        case loading
        case ready(CoachingAnswer)
        case failed(String)
    }

    enum NoteState: Equatable {
        case idle, saving, saved, failed
    }

    private(set) var phase: Phase = .loading
    private(set) var noteState: NoteState = .idle

    let record: CoachingRecord
    @ObservationIgnored private let assistant: any CoachingAsking
    @ObservationIgnored private let diary: any DiaryStore
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let newID: @Sendable () -> String
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        record: CoachingRecord, assistant: any CoachingAsking, diary: any DiaryStore, timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { .now },
        newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.record = record
        self.assistant = assistant
        self.diary = diary
        self.timeZone = timeZone
        self.now = now
        self.newID = newID
    }

    var answer: CoachingAnswer? {
        if case .ready(let answer) = phase { return answer }
        return nil
    }

    /// Una sola petición por hoja (un toque = un intento). Cerrar la hoja la cancela.
    func load() async {
        guard task == nil else { return }
        let task = Task { await ask() }
        self.task = task
        await task.value
    }

    func cancel() {
        task?.cancel()
    }

    private func ask() async {
        do {
            let answer = try await assistant.ask(record)
            guard !Task.isCancelled else { return }
            phase = .ready(answer)
        } catch is CancellationError {
            // Cerrada por el usuario: no es un fallo.
        } catch let error as LLMError {
            phase = .failed(error.description)
        } catch let error as CoachingAssistantError {
            phase = .failed(error.description)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Crea un evento `note` con el resumen, las sugerencias y la precaución. Una vez por respuesta.
    @discardableResult
    func saveNote() async -> Bool {
        guard let answer, noteState != .saving, noteState != .saved else { return false }
        noteState = .saving
        let text = CoachingNote.text(for: record, answer: answer)
        let event = CoachingNote.event(text: text, at: now(), timeZone: timeZone, newID: newID)
        do {
            try await diary.save(event)
            noteState = .saved
            return true
        } catch {
            noteState = .failed
            return false
        }
    }
}
