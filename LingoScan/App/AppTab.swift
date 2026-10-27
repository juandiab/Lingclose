import SwiftUI

/// Pestañas principales de la app.
enum AppTab: Hashable {
    case today, diary, reports, data, settings
}

/// Permite a una pantalla pedir otra pestaña sin conocer `RootTabView`.
struct TabSelector {
    var select: @MainActor (AppTab) -> Void = { _ in }

    @MainActor
    func callAsFunction(_ tab: AppTab) { select(tab) }
}

extension EnvironmentValues {
    @Entry var tabSelector = TabSelector()
}
