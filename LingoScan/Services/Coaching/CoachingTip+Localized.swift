import Foundation
import LingoCore

extension CoachingTip {
    /// Título traducido con la clave `coaching.<id>.title`; si falta, el texto por defecto en español de LingoCore.
    var localizedTitle: String { Self.resolve(titleKey, fallback: title) }
    /// Cuerpo traducido con la clave `coaching.<id>.body`.
    var localizedBody: String { Self.resolve(bodyKey, fallback: body) }

    private static func resolve(_ key: String, fallback: String) -> String {
        let value = String(localized: String.LocalizationValue(key))
        return value == key ? fallback : value
    }
}
