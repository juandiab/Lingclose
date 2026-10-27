import Foundation

/// Qué fuentes usa la app. Solo `-previewSensorState <caso>` (DEBUG) activa `PreviewData`;
/// sin ese argumento la app usa siempre SQLite y el coordinador reales.
enum AppLaunchMode: Equatable, Sendable {
    case live
    case preview(SensorPresentationState)

    static let previewArgumentKey = "previewSensorState"

    static func resolve(defaults: UserDefaults = .standard) -> AppLaunchMode {
        #if DEBUG
        if let raw = defaults.string(forKey: previewArgumentKey),
           let state = SensorPresentationState(rawValue: raw) {
            return .preview(state)
        }
        #endif
        return .live
    }

    var usesPreviewData: Bool {
        if case .preview = self { return true }
        return false
    }
}
