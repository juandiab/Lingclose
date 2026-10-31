/// Mini-curva de un día del período: 288 ranuras de 5 min de reloj local (mg/dL, `nil` sin lectura).
struct MedicalDailyProfile: Sendable, Hashable {
    var label: String
    var caption: String
    var values: [Int?]

    var hasData: Bool { values.contains { $0 != nil } }
}
