import LingoCore
import SwiftUI

/// Contenido del popover de un marcador: tipo, hora, gramos o duración, texto y, si hay datos, la respuesta
/// de la glucosa a la comida o el efecto del ejercicio (T-23, informativos).
struct DiaryMarkDetail: View {
    let mark: DiaryMark
    var mealResponse: MealResponse?
    var exerciseEffect: ExerciseEffect?
    /// Instante de referencia para decidir si una comida sin respuesta es "todavía" reciente.
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(mark.kind.title, systemImage: mark.kind.systemImage)
                .font(.headline)
            Text(mark.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let detail = mark.detail {
                Text(detail)
                    .monospacedDigit()
            }
            if let text = mark.text {
                Text(text)
            }
            DiaryMarkInsight(mark: mark, mealResponse: mealResponse, exerciseEffect: exerciseEffect, now: now)
                .font(.subheadline)
            if mark.synthetic {
                Text(String(localized: "today.mark.synthetic", defaultValue: "Ejemplo (sintético)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Tokens.Spacing.sm)
        // Ancho estable y alto propio: con la frase del insight el popover medía mal el texto envuelto y lo cortaba.
        .frame(minWidth: 220, idealWidth: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
