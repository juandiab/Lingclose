import SwiftUI

extension EnvironmentValues {
    /// Quien construye "Sugerir rango". Por defecto la previsualización; `RootTabView` inyecta el servicio real.
    @Entry var rangeSuggester: any RangeSuggesting = PreviewRangeSuggester()
}
