import SwiftUI

/// Pantalla provisional de Diario (T-06).
struct DiaryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: "diary.title", defaultValue: "Diario"),
                systemImage: "book.closed",
                description: Text(String(localized: "diary.placeholder", defaultValue: "Aquí registrarás comidas, ejercicio y notas."))
            )
            .navigationTitle(String(localized: "diary.title", defaultValue: "Diario"))
        }
    }
}

#Preview {
    DiaryView()
}
