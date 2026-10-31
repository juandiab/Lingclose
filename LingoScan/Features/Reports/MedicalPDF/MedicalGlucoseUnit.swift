import Foundation

/// Unidad en que el reporte para el médico muestra la glucosa (T-34). La app almacena mg/dL; mmol/L solo se usa al
/// presentar (1 mmol/L = 18,0156 mg/dL). Hoy el ajuste de la app es siempre mg/dL.
enum MedicalGlucoseUnit: String, Sendable, Hashable, CaseIterable {
    case mgdl
    case mmol

    static let mmolFactor = 18.0156

    var symbol: String { self == .mgdl ? "mg/dL" : "mmol/L" }

    /// De mg/dL a la unidad de presentación.
    func converted(_ mgdl: Double) -> Double { self == .mgdl ? mgdl : mgdl / Self.mmolFactor }

    /// Decimales con que se muestra un valor de glucosa (mg/dL enteros; mmol/L con uno).
    var decimals: Int { self == .mgdl ? 0 : 1 }

    /// Cortes del consenso internacional de tiempo en rango (Battelino 2019) en mg/dL.
    static let consensusCuts = [54, 70, 181, 251]
}
