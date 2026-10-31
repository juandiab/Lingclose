import Foundation
import LingoCore

/// Arma el `MedicalReportDocument` a partir del reporte calculado, los eventos y lo leído de Apple Salud (T-34).
/// Puro y determinista: mismo input, mismo documento. Las secciones de glucosa siempre van; las opcionales solo si el
/// usuario las dejó encendidas y hay datos. Informativo, no médico.
enum MedicalReportBuilder {
    /// Referencia de AGP y de las mini-curvas (mg/dL): el rango objetivo del consenso.
    static let targetLow = 70.0
    static let targetHigh = 180.0

    static func build(_ input: MedicalReportInput) -> MedicalReportDocument {
        let bundle = input.bundle
        let period = bundle.period
        let formatter = MedicalReportFormatter(locale: input.locale, timeZone: period.timeZone, unit: input.unit)
        let lastDay = max(period.start.date, period.end.date.addingTimeInterval(-1))
        let name = MedicalReportNameStore.normalized(input.patientName)
        let options = input.options

        let (rangeRows, personalRange) = rangeSection(bundle, formatter)
        let agp = agpSection(bundle, formatter)
        let daily = dailySection(bundle, formatter)
        return MedicalReportDocument(
            patientName: name,
            periodText: formatter.periodRange(period),
            generatedAtText: formatter.fullDateTime(input.generatedAt),
            isSynthetic: input.isSynthetic,
            unitSymbol: input.unit.symbol,
            fileName: "Lingclose-reporte-\(formatter.isoDay(period.start.date))_\(formatter.isoDay(lastDay)).pdf",
            patientFacts: patientFacts(input, name: name, formatter),
            periodFacts: periodFacts(bundle, formatter),
            metrics: metrics(bundle, formatter),
            rangeRows: rangeRows,
            personalRangeLine: personalRange,
            hasGlucoseData: bundle.hasData,
            agp: agp.chart,
            agpTable: agp.table,
            slots: slotsTable(bundle, formatter),
            weekly: weeklyTable(bundle, formatter),
            dailyProfiles: daily,
            dailyTitle: MedicalReportStrings.dailyTitle,
            dailySubtitle: MedicalReportStrings.dailySubtitle(input.unit.symbol),
            targetLow: targetLow,
            targetHigh: targetHigh,
            meals: options.meals ? mealsTable(input, formatter) : nil,
            nights: options.sleepActivity ? nightsTable(input, formatter) : nil,
            exercise: options.exercise ? exerciseTable(input, formatter) : nil,
            bodySummary: options.bodyComposition ? bodySummaryTable(input, formatter) : nil,
            bodyByDay: options.bodyComposition ? bodyByDayTable(input, formatter) : nil,
            notes: options.notes ? notesTable(input, formatter) : nil,
            methodNotes: methodNotes())
    }

    /// Una línea, sin espacios repetidos y de como mucho `limit` caracteres (con "…" si se corta); `nil` si queda vacía.
    static func oneLine(_ raw: String?, limit: Int) -> String? {
        guard let raw else { return nil }
        let line = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    private static func methodNotes() -> [String] {
        [MedicalReportStrings.methodSource, MedicalReportStrings.methodRanges, MedicalReportStrings.methodGMI,
         MedicalReportStrings.methodCV, MedicalReportStrings.methodAGP, MedicalReportStrings.methodCoverage,
         MedicalReportStrings.methodOther]
    }
}
