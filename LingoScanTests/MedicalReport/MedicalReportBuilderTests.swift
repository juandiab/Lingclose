import Foundation
import LingoCore
import Testing
@testable import LingoScan

/// T-34: `MedicalReportBuilder` es puro. Estas pruebas usan 14 días de datos inventados.
struct MedicalReportBuilderTests {
    // MARK: Cortes del consenso, GMI y CV

    @Test func consensusCutsAreFixedAndInclusive() {
        let series = ResampledSeries(
            start: UTCInstant(epochSeconds: 0), intervalMinutes: 5,
            values: [53, 54, 69, 70, 180, 181, 250, 251, nil, 39, 400])
        let range = MedicalTimeInRange(series: series)
        // <54: 53 y 39; 54–69: 54 y 69; 70–180: 70 y 180; 181–250: 181 y 250; >250: 251 y 400.
        #expect(range.counts == [2, 2, 2, 2, 2])
        #expect(range.total == 10)
        #expect(MedicalRangeBand.allCases.map { range.fraction($0) } == [0.2, 0.2, 0.2, 0.2, 0.2])
        #expect(MedicalRangeBand(mgdl: 53) == .veryLow && MedicalRangeBand(mgdl: 54) == .low)
        #expect(MedicalRangeBand(mgdl: 69) == .low && MedicalRangeBand(mgdl: 70) == .target)
        #expect(MedicalRangeBand(mgdl: 180) == .target && MedicalRangeBand(mgdl: 181) == .high)
        #expect(MedicalRangeBand(mgdl: 250) == .high && MedicalRangeBand(mgdl: 251) == .veryHigh)
    }

    @Test func timeInRangeWithoutReadingsIsEmpty() {
        let range = MedicalTimeInRange(series: ResampledSeries(start: UTCInstant(epochSeconds: 0), intervalMinutes: 5, values: [nil, nil]))
        #expect(!range.hasData)
        #expect(range.fraction(.target) == 0)
    }

    @Test func gmiFollowsTheConsensusFormula() {
        #expect(abs(MedicalReportBuilder.gmiPercent(meanMgdl: 100) - 5.702) < 1e-9)
        #expect(abs(MedicalReportBuilder.gmiPercent(meanMgdl: 154) - 6.99368) < 1e-9)
    }

    @Test func summaryMetricsMatchTheReportStats() async throws {
        let input = await MedicalReportFixtures.input()
        let document = MedicalReportBuilder.build(input)
        let stats = input.bundle.summary.stats
        let f = MedicalReportFormatter(locale: MedicalReportFixtures.locale, timeZone: MedicalReportFixtures.bogota)
        let mean = try #require(stats.mean)
        #expect(document.metrics.count == 4)
        #expect(document.metrics[0].value == f.glucose(mean))
        #expect(document.metrics[1].value == f.number(3.31 + 0.02392 * mean, decimals: 1) + " %")
        #expect(document.metrics[2].value == f.percent(stats.coefficientOfVariation, decimals: 1))
        #expect(document.metrics[3].value == f.glucose(stats.standardDeviation))
        // CV = DE / media (la que ya calcula el motor, redondeada a 3 decimales).
        let sd = try #require(stats.standardDeviation)
        let cv = try #require(stats.coefficientOfVariation)
        #expect(abs(cv - sd / mean) < 0.002)
    }

    @Test func rangeRowsUseTheFiveConsensusBandsAndSumToOne() async throws {
        let input = await MedicalReportFixtures.input()
        let document = MedicalReportBuilder.build(input)
        #expect(document.rangeRows.map(\.band) == MedicalRangeBand.allCases)
        #expect(document.rangeRows.map(\.rangeText) == ["<54", "54–69", "70–180", "181–250", ">250"])
        let total = document.rangeRows.reduce(0) { $0 + $1.fraction }
        #expect(abs(total - 1) < 1e-9)
        // Los datos de prueba tocan tramos altos y bajos.
        #expect(document.rangeRows[MedicalRangeBand.high.rawValue].fraction > 0)
        #expect(document.rangeRows[MedicalRangeBand.low.rawValue].fraction + document.rangeRows[MedicalRangeBand.veryLow.rawValue].fraction > 0)
        // Con 70–180 como rango personal no hay línea extra.
        #expect(document.personalRangeLine == nil)
    }

    @Test func personalRangeLineAppearsOnlyWhenItDiffersFromTheConsensus() async throws {
        let input = await MedicalReportFixtures.input(configuration: ReportConfiguration(range: 80...140))
        let document = MedicalReportBuilder.build(input)
        let line = try #require(document.personalRangeLine)
        #expect(line.contains("80") && line.contains("140") && line.contains("mg/dL"))
    }

    @Test func mmolUsesConvertedValuesAndCuts() async throws {
        let input = await MedicalReportFixtures.input(unit: .mmol)
        let document = MedicalReportBuilder.build(input)
        let f = MedicalReportFormatter(locale: MedicalReportFixtures.locale, timeZone: MedicalReportFixtures.bogota, unit: .mmol)
        let mean = try #require(input.bundle.summary.stats.mean)
        #expect(document.unitSymbol == "mmol/L")
        #expect(document.metrics[0].value == f.number(mean / 18.0156, decimals: 1))
        #expect(document.rangeRows.map(\.rangeText) == ["<3,0", "3,0–3,8", "3,9–10,0", "10,1–13,9", ">13,9"])
    }

    // MARK: Paciente

    @Test func patientFactsComeFromHealthAndMarkMissingOnes() async throws {
        let full = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        let labels = full.patientFacts.map(\.label)
        #expect(labels.count >= 7)
        #expect(full.patientFacts.first?.value == MedicalReportFixtures.testName)
        #expect(full.patientFacts.allSatisfy { $0.isAvailable })
        #expect(full.patientFacts.contains { $0.value.contains("O+") })
        #expect(full.patientFacts.contains { $0.value.contains("166") })

        let empty = MedicalReportBuilder.build(await MedicalReportFixtures.input(withHealth: false))
        // Todo lo de Salud falta, pero el PDF se arma igual.
        let missing = empty.patientFacts.filter { !$0.isAvailable }
        #expect(missing.count == empty.patientFacts.count - 1)
        #expect(missing.allSatisfy { $0.value == MedicalReportStrings.unavailable })
        #expect(empty.patientFacts.first?.isAvailable == true)
    }

    @Test func emptyNameShowsAsMissingAndIsNeverInTheFileName() async throws {
        let document = MedicalReportBuilder.build(await MedicalReportFixtures.input(name: "   "))
        #expect(document.patientName.isEmpty)
        #expect(document.patientFacts.first?.isAvailable == false)
        let named = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        #expect(!named.fileName.contains("Prueba") && !named.fileName.contains("Zeta"))
        let pattern = #/^Lingclose-reporte-\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}\.pdf$/#
        #expect(named.fileName.wholeMatch(of: pattern) != nil, "\(named.fileName)")
    }

    @Test func patientNameNeverReachesTheSnapshotJSON() async throws {
        let input = await MedicalReportFixtures.input()
        let document = MedicalReportBuilder.build(input)
        #expect(document.patientName == MedicalReportFixtures.testName)
        let json = try input.bundle.snapshot.compact().jsonData()
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("Zeta") && !text.contains("Prueba"))
        let exported = try ReportSnapshotExport(bundle: input.bundle).jsonData()
        #expect(!String(decoding: exported, as: UTF8.self).contains(MedicalReportFixtures.testName))
        let encoded = try JSONEncoder().encode(input.bundle.snapshot)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(MedicalReportFixtures.testName))
    }

    // MARK: Secciones opcionales

    @Test func optionalSectionsAppearWithDataAndOmitWhenSwitchedOff() async throws {
        let all = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        #expect(all.meals != nil && all.nights != nil && all.exercise != nil)
        #expect(all.bodySummary != nil && all.bodyByDay != nil && all.notes != nil)

        let off = MedicalReportBuilder.build(await MedicalReportFixtures.input(
            options: MedicalReportOptions(meals: false, sleepActivity: false, exercise: false, bodyComposition: false, notes: false)))
        #expect(off.meals == nil && off.nights == nil && off.exercise == nil)
        #expect(off.bodySummary == nil && off.bodyByDay == nil && off.notes == nil)
        // Las secciones de glucosa siempre van.
        #expect(off.agp.hasData && off.agpTable != nil && off.slots != nil && off.weekly != nil)
        #expect(!off.dailyProfiles.isEmpty)
    }

    @Test func optionalSectionsAreOmittedWithoutData() async throws {
        let bare = MedicalReportBuilder.build(await MedicalReportFixtures.input(withHealth: false, withDiary: false))
        #expect(bare.meals == nil && bare.exercise == nil && bare.notes == nil)
        #expect(bare.bodySummary == nil && bare.bodyByDay == nil)
        // Sin sueño ni pasos queda la glucosa nocturna, que viene del sensor.
        #expect(bare.nights != nil)
        #expect(bare.agp.hasData)
    }

    @Test func mealsTableJoinsNutritionAndGlucoseResponse() async throws {
        let input = await MedicalReportFixtures.input()
        let document = MedicalReportBuilder.build(input)
        let table = try #require(document.meals)
        #expect(table.rows.count == input.bundle.meals.meals.count)
        #expect(table.columns.count == 10 && table.rows.allSatisfy { $0.count == 10 })
        // Nombre del registro de nutrición, proteína y grasa estimadas.
        #expect(table.rows.contains { $0[1] == "Arepa con huevo y queso" && $0[3] == "24,5" && $0[4] == "17" })
        // Alguna comida tiene respuesta medida (antes, pico, subida y tiempo al pico).
        #expect(table.rows.contains { $0[6] != "—" && $0[7] != "—" && $0[8].hasPrefix("+") && $0[9] != "—" })
        // Ordenadas por hora.
        let times = input.bundle.meals.meals.map(\.at).sorted()
        #expect(times.count == table.rows.count)
    }

    @Test func nightsTableJoinsSleepAndStepsByDate() async throws {
        let input = await MedicalReportFixtures.input()
        let table = try #require(MedicalReportBuilder.build(input).nights)
        #expect(table.columns.count == 8 && table.rows.allSatisfy { $0.count == 8 })
        #expect(table.rows.count >= 13)
        // Hay noches con glucosa, sueño y pasos a la vez.
        #expect(table.rows.contains { !$0.contains("—") })
        #expect(table.subtitle?.isEmpty == false)
    }

    @Test func bodyTablesListMeasurementsWithFirstLastAndChange() async throws {
        let input = await MedicalReportFixtures.input()
        let summary = try #require(MedicalReportBuilder.build(input).bodySummary)
        #expect(summary.rows.count == 5)
        let weight = try #require(summary.rows.first)
        #expect(weight[0] == MedicalReportStrings.weightKg)
        #expect(weight[3].hasPrefix("−"), "El peso de prueba baja: \(weight)")
        let byDay = try #require(MedicalReportBuilder.build(input).bodyByDay)
        #expect(byDay.columns.count == 6)
        #expect(byDay.rows.count == input.bodySeries.measurements(.weight).count)
    }

    @Test func notesListOnlyDiaryNotesOfThePeriodInOneLine() async throws {
        var input = await MedicalReportFixtures.input()
        let at = input.bundle.period.start.adding(seconds: 5 * 86_400)
        input.events.append(MedicalReportFixtures.event(.note, at: at, text: "  línea uno\nlínea   dos  "))
        // Fuera del período y borrada: no cuentan.
        input.events.append(MedicalReportFixtures.event(.note, at: input.bundle.period.start.adding(seconds: -86_400), text: "ANTERIOR"))
        var deleted = MedicalReportFixtures.event(.note, at: at.adding(seconds: 60), text: "BORRADA")
        deleted.deleted = true
        input.events.append(deleted)
        let table = try #require(MedicalReportBuilder.build(input).notes)
        let all = table.rows.map { $0[2] }
        #expect(all.contains("línea uno línea dos"))
        #expect(!all.contains("ANTERIOR") && !all.contains("BORRADA"))
        #expect(!all.contains { $0.contains("\n") })
    }

    @Test func dailyProfilesCoverEveryDayOfThePeriod() async throws {
        let input = await MedicalReportFixtures.input()
        let document = MedicalReportBuilder.build(input)
        #expect(document.dailyProfiles.count == input.bundle.dailyOverlay.days.count)
        #expect(document.dailyProfiles.allSatisfy { $0.values.count == DailyOverlayReport.slotCount })
        #expect(document.dailyProfiles.contains { $0.hasData })
    }

    @Test func agpTableSummarisesTwoHourWindows() async throws {
        let document = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        let table = try #require(document.agpTable)
        #expect(table.columns.count == 13 && table.rows.count == 4)
        #expect(table.columns[1].title == "00–02" && table.columns[12].title == "22–24")
        let median = table.rows[0].dropFirst().compactMap { Int($0) }
        #expect(median.count == 12 && median.allSatisfy { (40...300).contains($0) })
        #expect(document.agp.points.allSatisfy { $0.p5 <= $0.p25 && $0.p25 <= $0.p50 && $0.p50 <= $0.p75 && $0.p75 <= $0.p95 })
    }

    @Test func syntheticFlagAndSensorLineAreCarried() async throws {
        let document = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        #expect(document.isSynthetic)
        #expect(document.periodFacts.contains { $0.value.contains("FreeStyle Libre 3") })
        // Sin número de serie ni Receiver ID.
        #expect(!document.periodFacts.contains { $0.label.lowercased().contains("serial") })
        #expect(document.methodNotes.count == 7)
        let real = MedicalReportBuilder.build(await MedicalReportFixtures.input(isSynthetic: false))
        #expect(!real.isSynthetic)
    }
}
