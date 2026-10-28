import SwiftUI

/// Cabecera compacta de Hoy: valor, tendencia y estado a la izquierda; chip del sensor arriba a la derecha.
/// Con tamaños de accesibilidad la chip pasa debajo para no comprimir el valor.
struct TodayHeader: View {
    let viewModel: TodayViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tokens.Spacing.xs))
        layout {
            // El último valor es independiente de la ventana visible: se ve también al mirar otro día.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                CurrentValueView(viewModel: viewModel, now: context.date)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SensorStatusChip(state: viewModel.sensor.state)
        }
    }
}
