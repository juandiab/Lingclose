/// Subpantallas de Ajustes. Se registran una sola vez con `navigationDestination(for:)` en `SettingsView`.
enum SettingsRoute: Hashable {
    case referenceRange
    case alerts
    case health
    case assistant
    case identity
    case permissions
    case technicalInfo
}
