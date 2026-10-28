import SwiftUI

extension EnvironmentValues {
    /// Tarjeta "Qué hacer" de Hoy (T-25); `nil` sin alertas (previsualización sin `-previewCoaching`).
    @Entry var coaching: CoachingController?
}
