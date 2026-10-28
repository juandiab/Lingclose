import Foundation

/// Perfil de Salud leído solo para "Sugerir rango": edad (por fecha de nacimiento), sexo biológico y el peso y
/// la altura más recientes. Lo que Salud no tenga queda `nil` y la hoja lo dice. No se guarda en SQLite ni se
/// exporta: vive el tiempo que dura la hoja.
struct HealthProfile: Sendable, Equatable {
    var ageYears: Int?
    var biologicalSex: BiologicalSexSummary?
    var weightKg: Double?
    var heightCm: Double?

    static let empty = HealthProfile()

    /// Índice de masa corporal (kg/m²), solo si hay peso y altura válidos.
    var bodyMassIndex: Double? {
        guard let weightKg, let heightCm, weightKg > 0, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    var missingFields: [HealthProfileField] {
        HealthProfileField.allCases.filter { field in
            switch field {
            case .age: ageYears == nil
            case .sex: biologicalSex == nil
            case .weight: weightKg == nil
            case .height: heightCm == nil
            }
        }
    }

    var isEmpty: Bool { missingFields.count == HealthProfileField.allCases.count }
}

/// Lo que se envía al asistente (`rawValue`) y se muestra en la hoja.
enum BiologicalSexSummary: String, Sendable, Equatable {
    case female, male, other
}

enum HealthProfileField: CaseIterable, Sendable, Equatable {
    case age, sex, weight, height
}
