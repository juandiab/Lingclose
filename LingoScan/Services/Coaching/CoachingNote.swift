import Foundation
import LingoCore

/// Texto y evento `note` del diario con la respuesta del asistente ("Guardar como nota", T-25).
enum CoachingNote {
    /// Igual que `DiaryViewModel.appID` (aislado al actor principal).
    static let appID = "com.otalvaro.lingoscan"

    static func text(for record: CoachingRecord, answer: CoachingAnswer) -> String {
        let reply = answer.reply
        var lines = [header(for: record.context), reply.summary]
        lines += reply.suggestions.map { "• \($0.title): \($0.body)" }
        if let caution = reply.caution { lines.append(caution) }
        lines.append(String(localized: "coaching.note.footer", defaultValue: "Informativo, no es consejo médico."))
        return lines.joined(separator: "\n")
    }

    /// "Asistente · alerta Alta, 165 mg/dL".
    static func header(for context: CoachingContext) -> String {
        if let value = context.value {
            return String(localized: "coaching.note.header", defaultValue: "Asistente · alerta \(context.kind.settingsTitle), \(value) mg/dL")
        }
        return String(localized: "coaching.note.header.noValue", defaultValue: "Asistente · alerta \(context.kind.settingsTitle)")
    }

    static func event(text: String, at date: Date, timeZone: TimeZone, newID: () -> String) -> DiaryEvent {
        let instant = UTCInstant(date)
        return DiaryEvent(
            eventID: newID(), kind: .note, at: instant, tz: timeZone.identifier, text: text,
            createdAt: instant, updatedAt: instant, revision: 1, editID: newID(), parentEditID: nil,
            editedByAppID: appID, deleted: false, synthetic: false)
    }
}
