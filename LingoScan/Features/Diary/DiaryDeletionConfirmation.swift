import LingoCore
import SwiftUI

/// Diálogo "¿Borrar este registro?" del Diario y del registro de Hoy. El borrado se aplica cuando el diálogo ya se
/// cerró (`DiaryViewModel.hasDeletionReadyToCommit`), en una sola actualización de la lista (T-32).
struct DiaryDeletionConfirmation: ViewModifier {
    @Bindable var viewModel: DiaryViewModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                String(localized: "diary.delete.title", defaultValue: "¿Borrar este registro?"),
                isPresented: $viewModel.isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: viewModel.pendingDeletion
            ) { event in
                Button(String(localized: "diary.delete.confirm", defaultValue: "Borrar"), role: .destructive) {
                    viewModel.confirmDeletion(event)
                }
            } message: { _ in
                Text(String(localized: "diary.delete.message", defaultValue: "Se conserva el historial de ediciones; el registro deja de mostrarse."))
            }
            .onChange(of: viewModel.hasDeletionReadyToCommit) { _, isReady in
                guard isReady else { return }
                Task { await viewModel.commitConfirmedDeletion() }
            }
    }
}

extension View {
    /// Confirmación de borrado de un registro del diario.
    func diaryDeletionConfirmation(_ viewModel: DiaryViewModel) -> some View {
        modifier(DiaryDeletionConfirmation(viewModel: viewModel))
    }
}
