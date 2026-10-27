import Foundation
import LingoCore

/// Hoja de alta o edición abierta. `editing == nil` es un alta.
struct DiaryEditor: Identifiable {
    let id = UUID()
    let editing: DiaryEvent?
    var draft: DiaryDraft
}
