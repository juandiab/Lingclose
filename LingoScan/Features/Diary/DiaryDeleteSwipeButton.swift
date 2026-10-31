import LingoCore
import SwiftUI

/// Acción de deslizar "Borrar" de una fila del diario: solo abre el diálogo de confirmación.
///
/// Sin `role: .destructive` a propósito (T-32): con ese rol, `List` quita la fila de la colección en el mismo toque
/// suponiendo que los datos ya la borraron; como aquí el borrado espera al diálogo, la siguiente actualización
/// encontraba una fila de más y `UICollectionView` abortaba ("invalid number of items in section").
struct DiaryDeleteSwipeButton: View {
    let viewModel: DiaryViewModel
    let event: DiaryEvent

    var body: some View {
        Button(String(localized: "diary.delete.confirm", defaultValue: "Borrar"), systemImage: "trash") {
            viewModel.pendingDeletion = event
        }
        .tint(.red)
    }
}
