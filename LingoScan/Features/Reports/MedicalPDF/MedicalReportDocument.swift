/// El reporte para el médico ya armado y formateado (T-34): lo único que `MedicalPDFRenderer` necesita. Puro y
/// `Sendable`; lo arma `MedicalReportBuilder` sin tocar HealthKit ni la red. El nombre vive aquí solo para dibujarlo en
/// el PDF; nunca se serializa a ningún otro sitio.
struct MedicalReportDocument: Sendable {
    var patientName: String
    var periodText: String
    var generatedAtText: String
    var isSynthetic: Bool
    var unitSymbol: String
    /// `Lingclose-reporte-<aaaa-mm-dd>_<aaaa-mm-dd>.pdf`, sin el nombre.
    var fileName: String

    // Página 1
    var patientFacts: [MedicalFact]
    var periodFacts: [MedicalFact]
    var metrics: [MedicalFact]
    var rangeRows: [MedicalRangeRow]
    var personalRangeLine: String?
    var hasGlucoseData: Bool

    // Glucosa (siempre)
    var agp: MedicalAGP
    var agpTable: MedicalTable?
    var slots: MedicalTable?
    var weekly: MedicalTable?
    var dailyProfiles: [MedicalDailyProfile]
    var dailyTitle: String
    var dailySubtitle: String
    /// Rango objetivo de las mini-curvas (mg/dL).
    var targetLow: Double
    var targetHigh: Double

    // Opcionales
    var meals: MedicalTable?
    var nights: MedicalTable?
    var exercise: MedicalTable?
    var bodySummary: MedicalTable?
    var bodyByDay: MedicalTable?
    var notes: MedicalTable?

    var methodNotes: [String]
}
