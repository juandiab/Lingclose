import Foundation

/// Nombre que aparece en el reporte en PDF para el médico (T-34). Vive solo en el dispositivo (`UserDefaults`, clave
/// versionada) y se edita en dos sitios: Ajustes › Reporte médico y la hoja previa de Reportes › Compartir. Nunca va al
/// JSON de Compartir, al análisis con IA, a logs ni a `event_log`.
struct MedicalReportNameStore: Sendable {
    /// Clave de `UserDefaults` (y de `@AppStorage`). El sufijo `.v1` permite cambiar el formato sin leer basura.
    static let key = "lingoscan.report.patient_name.v1"
    static let maxLength = 80

    private let defaults: UserDefaultsBox

    init(defaults: UserDefaults = .standard) {
        self.defaults = UserDefaultsBox(defaults)
    }

    var name: String {
        get { Self.normalized(defaults.value.string(forKey: Self.key) ?? "") }
        nonmutating set {
            let clean = Self.normalized(newValue)
            if clean.isEmpty {
                defaults.value.removeObject(forKey: Self.key)
            } else {
                defaults.value.set(clean, forKey: Self.key)
            }
        }
    }

    /// Una sola línea, sin espacios repetidos ni en los extremos, de como mucho `maxLength` caracteres.
    static func normalized(_ raw: String) -> String {
        let oneLine = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(oneLine.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// `UserDefaults` es seguro entre hilos pero no está marcado `Sendable` en el SDK.
    private struct UserDefaultsBox: @unchecked Sendable {
        let value: UserDefaults
        init(_ value: UserDefaults) { self.value = value }
    }
}
