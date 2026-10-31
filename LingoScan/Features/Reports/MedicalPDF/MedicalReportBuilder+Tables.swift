import Foundation
import LingoCore

extension MedicalReportBuilder {
    private static let dash = MedicalReportFormatter.dash
    static let maxNotes = 150

    // MARK: Comidas

    static func mealsTable(_ input: MedicalReportInput, _ f: MedicalReportFormatter) -> MedicalTable? {
        let meals = input.bundle.meals.meals
        guard !meals.isEmpty else { return nil }
        var eventAt: [UTCInstant: DiaryEvent] = [:]
        for event in input.events where event.kind == .meal && !event.deleted && eventAt[event.at] == nil {
            eventAt[event.at] = event
        }
        let rows = meals.sorted { $0.at < $1.at }.map { meal -> [String] in
            let event = eventAt[meal.at]
            let record = event.flatMap { input.nutrition[$0.eventID] }
            let nutrients = record?.effectiveNutrients ?? .unknown
            let name = oneLine(record?.name, limit: 80) ?? oneLine(event?.text, limit: 80) ?? S.mealDefault
            func grams(_ value: Double?) -> String { value.map { f.flexible($0) } ?? dash }
            let response = meal.response
            return [
                f.dayAndTime(meal.at.date) + (meal.overlapsPreviousMeal ? " †" : ""), name,
                grams(nutrients.carbsG ?? meal.carbsG), grams(nutrients.proteinG), grams(nutrients.fatG),
                nutrients.kcal.map { f.number($0) } ?? dash,
                response.map { f.glucose($0.baseline) } ?? dash, response.map { f.glucose(Double($0.peak)) } ?? dash,
                response.map { f.glucoseDelta($0.rise) } ?? dash,
                response.map { f.duration(minutes: $0.timeToPeakMinutes) } ?? dash,
            ]
        }
        let columns = [
            MedicalTableColumn(title: S.dateTime, weight: 3.6, alignment: .leading),
            MedicalTableColumn(title: S.meal, weight: 5.4, alignment: .leading),
            MedicalTableColumn(title: S.carbs, weight: 1.7), MedicalTableColumn(title: S.protein, weight: 1.7),
            MedicalTableColumn(title: S.fat, weight: 1.7), MedicalTableColumn(title: S.kcal, weight: 1.7),
            MedicalTableColumn(title: S.before, weight: 1.6), MedicalTableColumn(title: S.peak, weight: 1.6),
            MedicalTableColumn(title: S.rise, weight: 1.7), MedicalTableColumn(title: S.timeToPeak, weight: 2.1),
        ]
        return MedicalTable(id: "meals", title: S.mealsTitle, subtitle: S.mealsSubtitle(f.unit.symbol), columns: columns,
                            rows: rows, rowHeight: MedicalTable.doubleLineRow)
    }

    // MARK: Noches, sueño y pasos

    static func nightsTable(_ input: MedicalReportInput, _ f: MedicalReportFormatter) -> MedicalTable? {
        let bundle = input.bundle
        guard let firstDay = bundle.summary.days.first?.day, let lastDay = bundle.summary.days.last?.day else { return nil }
        // La noche que empieza el día anterior al primero también se lista.
        let lowerBound = f.isoDay(firstDay.start.date.addingTimeInterval(-12 * 3_600))
        let upperBound = lastDay.date
        func inPeriod(_ day: String) -> Bool { day >= lowerBound && day <= upperBound }

        let nights = Dictionary(bundle.nights.nights.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        let sleep = Dictionary(input.sleep.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        let steps = Dictionary(input.steps.filter { $0.steps > 0 }.map { ($0.day, $0.steps) }, uniquingKeysWith: { first, _ in first })
        let days = Set(nights.keys).union(sleep.keys).union(steps.keys).filter(inPeriod).sorted()
        guard !days.isEmpty else { return nil }

        let rows = days.map { day -> [String] in
            let night = nights[day]
            let slept = sleep[day]
            return [
                f.weekdayDay(iso: day) + (night.map { $0.isReliable ? "" : " ‡" } ?? ""),
                night?.median.map { f.glucose($0) } ?? dash,
                night?.stats.minimum.map { f.glucose(Double($0)) } ?? dash,
                night.map { f.percent($0.stats.timeInRange) } ?? dash,
                night.map { String($0.lowEpisodes) } ?? dash,
                slept.map { f.duration(minutes: $0.asleepMin) } ?? dash,
                slept.map { String($0.awakenings) } ?? dash,
                steps[day].map { f.integer($0) } ?? dash,
            ]
        }
        var subtitle = S.nightsSubtitle(f.unit.symbol)
        if !steps.isEmpty {
            let average = Double(steps.values.reduce(0, +)) / Double(steps.count)
            subtitle += " " + S.averageSteps(f.integer(Int(average.rounded())))
        }
        let columns = [
            MedicalTableColumn(title: S.nightColumn, weight: 2.4, alignment: .leading),
            MedicalTableColumn(title: S.median, weight: 1.5), MedicalTableColumn(title: S.minimum, weight: 1.5),
            MedicalTableColumn(title: S.inRange, weight: 1.5), MedicalTableColumn(title: S.lowEpisodes, weight: 1.8),
            MedicalTableColumn(title: S.asleep, weight: 1.8), MedicalTableColumn(title: S.awakenings, weight: 1.8),
            MedicalTableColumn(title: S.steps, weight: 1.6),
        ]
        return MedicalTable(id: "nights", title: S.nightsTitle, subtitle: subtitle, columns: columns, rows: rows)
    }

    // MARK: Ejercicio

    static func exerciseTable(_ input: MedicalReportInput, _ f: MedicalReportFormatter) -> MedicalTable? {
        let sessions = input.bundle.exercise.sessions
        guard !sessions.isEmpty else { return nil }
        var eventAt: [UTCInstant: DiaryEvent] = [:]
        for event in input.events where event.kind == .exercise && !event.deleted && eventAt[event.at] == nil {
            eventAt[event.at] = event
        }
        let rows = sessions.sorted { $0.at < $1.at }.map { session -> [String] in
            let effect = session.effect
            return [
                f.dayAndTime(session.at.date), oneLine(eventAt[session.at]?.text, limit: 60) ?? S.exerciseDefault,
                session.durationMinutes.map { f.duration(minutes: $0) } ?? dash,
                effect.map { f.glucose($0.baseline) } ?? dash, f.glucoseDelta(effect?.deltaAtEnd),
                f.glucoseDelta(effect?.deltaAt60), f.glucoseDelta(effect?.deltaAt120),
                effect.map { "\(f.glucose(Double($0.minimum))) (\(f.glucoseDelta($0.dropToMinimum)))" } ?? dash,
            ]
        }
        let columns = [
            MedicalTableColumn(title: S.dateTime, weight: 3.4, alignment: .leading),
            MedicalTableColumn(title: S.exerciseType, weight: 4, alignment: .leading),
            MedicalTableColumn(title: S.duration, weight: 1.8), MedicalTableColumn(title: S.baseline, weight: 1.5),
            MedicalTableColumn(title: S.atEnd, weight: 1.8), MedicalTableColumn(title: S.after60, weight: 1.6),
            MedicalTableColumn(title: S.after120, weight: 1.6), MedicalTableColumn(title: S.lowest, weight: 2.4),
        ]
        return MedicalTable(id: "exercise", title: S.exerciseTitle, subtitle: S.exerciseSubtitle(f.unit.symbol),
                            columns: columns, rows: rows, rowHeight: MedicalTable.doubleLineRow)
    }

    // MARK: Composición corporal

    private struct BodyColumn {
        var metric: BodyMetric
        var title: String
        var decimals: Int
    }

    private static var bodyColumns: [BodyColumn] {
        [BodyColumn(metric: .weight, title: S.weightKg, decimals: 1), BodyColumn(metric: .bodyFat, title: S.bodyFat, decimals: 1),
         BodyColumn(metric: .leanMass, title: S.leanMass, decimals: 1), BodyColumn(metric: .bmi, title: S.bmiUnit, decimals: 1),
         BodyColumn(metric: .waist, title: S.waist, decimals: 1)]
    }

    /// Primera, última y cambio de cada medida con mediciones en el período. Solo cifras.
    static func bodySummaryTable(_ input: MedicalReportInput, _ f: MedicalReportFormatter) -> MedicalTable? {
        var rows: [[String]] = []
        for column in bodyColumns {
            let samples = input.bodySeries.measurements(column.metric)
            guard let first = samples.first, let last = samples.last else { continue }
            func value(_ m: BodyMeasurement) -> String { "\(f.flexible(m.value, maxDecimals: column.decimals)) · \(f.shortDay(m.date))" }
            rows.append([
                column.title, value(first), value(last),
                samples.count > 1 ? f.signed(last.value - first.value, decimals: column.decimals) : dash,
                String(samples.count),
            ])
        }
        guard !rows.isEmpty else { return nil }
        let columns = [
            MedicalTableColumn(title: S.measure, weight: 3, alignment: .leading),
            MedicalTableColumn(title: S.first, weight: 2.4), MedicalTableColumn(title: S.last, weight: 2.4),
            MedicalTableColumn(title: S.change, weight: 1.6), MedicalTableColumn(title: S.measurements, weight: 1.8),
        ]
        return MedicalTable(id: "bodySummary", title: S.bodyTitle, subtitle: S.bodySubtitle, columns: columns, rows: rows)
    }

    /// Una fila por día con la última medición de cada medida de ese día.
    static func bodyByDayTable(_ input: MedicalReportInput, _ f: MedicalReportFormatter) -> MedicalTable? {
        let columns = bodyColumns
        var byDay: [String: [BodyMetric: Double]] = [:]
        for column in columns {
            for sample in input.bodySeries.measurements(column.metric) {
                byDay[f.isoDay(sample.date), default: [:]][column.metric] = sample.value
            }
        }
        guard !byDay.isEmpty else { return nil }
        let rows = byDay.keys.sorted().map { day -> [String] in
            [f.weekdayDay(iso: day)] + columns.map { column in
                byDay[day]?[column.metric].map { f.flexible($0, maxDecimals: column.decimals) } ?? dash
            }
        }
        let tableColumns = [MedicalTableColumn(title: S.date, weight: 2.6, alignment: .leading)]
            + columns.map { MedicalTableColumn(title: $0.title, weight: 2) }
        return MedicalTable(id: "bodyByDay", title: S.bodyByDayTitle, subtitle: nil, columns: tableColumns, rows: rows)
    }

    // MARK: Notas del diario

    static func notesTable(_ input: MedicalReportInput, _ f: MedicalReportFormatter) -> MedicalTable? {
        let period = input.bundle.period
        let notes = input.events
            .filter { ($0.kind == .note || $0.kind == .sensorNote) && !$0.deleted && period.contains($0.at) }
            .sorted { $0.at < $1.at }
            .compactMap { event -> [String]? in
                guard let text = oneLine(event.text, limit: 240) else { return nil }
                return [f.dayAndTime(event.at.date), event.kind == .note ? S.note : S.sensorNote, text]
            }
        guard !notes.isEmpty else { return nil }
        var rows = Array(notes.prefix(maxNotes))
        if notes.count > maxNotes { rows.append(["", "", S.moreNotes(notes.count - maxNotes)]) }
        let columns = [
            MedicalTableColumn(title: S.dateTime, weight: 3, alignment: .leading),
            MedicalTableColumn(title: S.noteKind, weight: 2.4, alignment: .leading),
            MedicalTableColumn(title: S.note, weight: 11, alignment: .leading),
        ]
        return MedicalTable(id: "notes", title: S.notesTitle, subtitle: S.notesSubtitle, columns: columns, rows: rows,
                            rowHeight: MedicalTable.doubleLineRow)
    }
}
