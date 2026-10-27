import Foundation

/// Lo que monta `LingoScanApp`: servicios reales, previsualización o fallo al abrir la base.
@MainActor
enum AppRoot {
    case live(AppEnvironment)
    case preview(SensorPresentationState)
    case failed(String)

    static func make(mode: AppLaunchMode = .resolve()) -> AppRoot {
        switch mode {
        case .preview(let state):
            return .preview(state)
        case .live:
            do {
                let environment = try AppEnvironment.live()
                environment.start()
                return .live(environment)
            } catch {
                return .failed(String(describing: type(of: error)))
            }
        }
    }
}
