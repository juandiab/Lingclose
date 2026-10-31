import Foundation

/// Textos del reporte en PDF para el médico (T-34), todos localizados (es fuente, en, pt-BR). Términos clínicos
/// estándar: "tiempo en rango", "GMI", "coeficiente de variación". Los textos de la hoja y de Ajustes viven en sus vistas.
enum MedicalReportStrings {
    // MARK: Encabezado, pie y marca de agua

    static var documentTitle: String {
        String(localized: "medical.pdf.title", defaultValue: "Reporte de glucosa para el médico")
    }
    static var documentSubtitle: String {
        String(localized: "medical.pdf.subtitle", defaultValue: "Resumen y perfil de glucosa ambulatorio (AGP)")
    }
    static func page(_ number: Int, of count: Int) -> String {
        String(localized: "medical.pdf.footer.page", defaultValue: "Página \(number) de \(count)")
    }
    static func generated(_ text: String) -> String {
        String(localized: "medical.pdf.footer.generated", defaultValue: "Generado el \(text)")
    }
    static var disclaimer: String {
        String(localized: "medical.pdf.footer.disclaimer", defaultValue: "Lingclose no es un dispositivo médico; no sustituye el criterio de un profesional de salud.")
    }
    static var watermark: String {
        String(localized: "medical.pdf.watermark", defaultValue: "DATOS DE EJEMPLO")
    }
    static var syntheticNote: String {
        String(localized: "medical.pdf.synthetic", defaultValue: "Datos de ejemplo (sintéticos). No son de un sensor real.")
    }

    // MARK: Página 1

    static var patientTitle: String {
        String(localized: "medical.pdf.patient.title", defaultValue: "Datos del paciente")
    }
    static var name: String { String(localized: "medical.pdf.patient.name", defaultValue: "Nombre") }
    static var noName: String { String(localized: "medical.pdf.patient.noName", defaultValue: "Sin nombre") }
    static var birthDate: String { String(localized: "medical.pdf.patient.birthDate", defaultValue: "Fecha de nacimiento") }
    static var age: String { String(localized: "medical.pdf.patient.age", defaultValue: "Edad") }
    static func years(_ count: Int) -> String {
        String(localized: "medical.pdf.patient.years", defaultValue: "\(count) años")
    }
    static var sex: String { String(localized: "medical.pdf.patient.sex", defaultValue: "Sexo biológico") }
    static var female: String { String(localized: "medical.pdf.patient.sex.female", defaultValue: "Femenino") }
    static var male: String { String(localized: "medical.pdf.patient.sex.male", defaultValue: "Masculino") }
    static var otherSex: String { String(localized: "medical.pdf.patient.sex.other", defaultValue: "Otro") }
    static var bloodType: String { String(localized: "medical.pdf.patient.bloodType", defaultValue: "Grupo sanguíneo") }
    static var height: String { String(localized: "medical.pdf.patient.height", defaultValue: "Altura") }
    static var weight: String { String(localized: "medical.pdf.patient.weight", defaultValue: "Peso") }
    static var weightChange: String {
        String(localized: "medical.pdf.patient.weightChange", defaultValue: "Cambio de peso en el período")
    }
    static var bmi: String { String(localized: "medical.pdf.patient.bmi", defaultValue: "IMC") }
    static var unavailable: String {
        String(localized: "medical.pdf.patient.unavailable", defaultValue: "No disponible en Apple Salud")
    }

    static var periodTitle: String { String(localized: "medical.pdf.period.title", defaultValue: "Período del reporte") }
    static var period: String { String(localized: "medical.pdf.period", defaultValue: "Período") }
    static var daysLabel: String { String(localized: "medical.pdf.period.daysLabel", defaultValue: "Días con datos") }
    static func daysOf(_ days: Int, of total: Int) -> String {
        String(localized: "medical.pdf.period.daysOf", defaultValue: "\(days) de \(total)")
    }
    static var sensor: String { String(localized: "medical.pdf.sensor", defaultValue: "Sensor") }
    static var sensorName: String {
        String(localized: "medical.pdf.sensor.name", defaultValue: "Abbott Lingo (plataforma FreeStyle Libre 3)")
    }
    static var sensorActive: String {
        String(localized: "medical.pdf.sensor.active", defaultValue: "Tiempo con sensor activo")
    }
    static var readings: String { String(localized: "medical.pdf.sensor.readings", defaultValue: "Lecturas") }

    static var metricsTitle: String { String(localized: "medical.pdf.metrics.title", defaultValue: "Métricas de glucosa") }
    static func meanGlucose(_ unit: String) -> String {
        String(localized: "medical.pdf.metrics.mean", defaultValue: "Glucosa media (\(unit))")
    }
    static var gmi: String {
        String(localized: "medical.pdf.metrics.gmi", defaultValue: "GMI (indicador de gestión de glucosa)")
    }
    static var cv: String {
        String(localized: "medical.pdf.metrics.cv", defaultValue: "Coeficiente de variación (CV)")
    }
    static func sd(_ unit: String) -> String {
        String(localized: "medical.pdf.metrics.sd", defaultValue: "Desviación estándar (\(unit))")
    }

    static func rangesTitle(_ unit: String) -> String {
        String(localized: "medical.pdf.ranges.title", defaultValue: "Tiempo en rangos (\(unit))")
    }
    static var rangesPerDay: String { String(localized: "medical.pdf.ranges.perDay", defaultValue: "Por día") }
    static var veryLow: String { String(localized: "medical.pdf.ranges.veryLow", defaultValue: "Muy bajo") }
    static var low: String { String(localized: "medical.pdf.ranges.low", defaultValue: "Bajo") }
    static var inRange: String { String(localized: "medical.pdf.ranges.inRange", defaultValue: "En rango") }
    static var high: String { String(localized: "medical.pdf.ranges.high", defaultValue: "Alto") }
    static var veryHigh: String { String(localized: "medical.pdf.ranges.veryHigh", defaultValue: "Muy alto") }
    static func personalRange(_ low: String, _ high: String, _ unit: String, _ share: String) -> String {
        String(localized: "medical.pdf.ranges.personal",
               defaultValue: "Rango personal configurado: \(low)–\(high) \(unit) · \(share) del tiempo")
    }

    // MARK: AGP, franjas, semanas, perfiles diarios

    static var agpTitle: String {
        String(localized: "medical.pdf.agp.title", defaultValue: "Perfil de glucosa ambulatorio (AGP)")
    }
    static func agpSubtitle(_ unit: String) -> String {
        String(localized: "medical.pdf.agp.subtitle",
               defaultValue: "Mediana y percentiles por hora del día con todos los días del período superpuestos (\(unit)). Banda verde: rango objetivo.")
    }
    static var agpMedian: String { String(localized: "medical.pdf.agp.median", defaultValue: "Mediana") }
    static var agpIQR: String { String(localized: "medical.pdf.agp.iqr", defaultValue: "Percentil 25–75") }
    static var agpWide: String { String(localized: "medical.pdf.agp.wide", defaultValue: "Percentil 5–95") }
    static var agpTarget: String { String(localized: "medical.pdf.agp.target", defaultValue: "Rango objetivo") }
    static var agpTableTitle: String {
        String(localized: "medical.pdf.agp.table.title", defaultValue: "Valores por franja de 2 horas")
    }
    static var agpHour: String { String(localized: "medical.pdf.agp.table.hour", defaultValue: "Hora") }
    static var agpDays: String { String(localized: "medical.pdf.agp.table.days", defaultValue: "Días") }
    static var agpNoData: String {
        String(localized: "medical.pdf.agp.noData", defaultValue: "No hay suficientes días para dibujar el perfil.")
    }

    static var slotsTitle: String { String(localized: "medical.pdf.slots.title", defaultValue: "Franjas del día") }
    static var slotsSubtitle: String {
        String(localized: "medical.pdf.slots.subtitle",
               defaultValue: "Todas las lecturas del período en cada franja de hora local.")
    }
    static var slot: String { String(localized: "medical.pdf.slots.slot", defaultValue: "Franja") }
    static var morning: String { String(localized: "medical.pdf.slots.morning", defaultValue: "Mañana (6–11 h)") }
    static var midday: String { String(localized: "medical.pdf.slots.midday", defaultValue: "Mediodía (11–16 h)") }
    static var evening: String { String(localized: "medical.pdf.slots.evening", defaultValue: "Tarde (16–22 h)") }
    static var night: String { String(localized: "medical.pdf.slots.night", defaultValue: "Noche (22–6 h)") }
    static var mean: String { String(localized: "medical.pdf.col.mean", defaultValue: "Media") }
    static func inRangeColumn(_ low: String, _ high: String) -> String {
        String(localized: "medical.pdf.col.inRange", defaultValue: "En rango \(low)–\(high)")
    }
    static var sdShort: String { String(localized: "medical.pdf.col.sd", defaultValue: "DE") }
    static var fastRises: String { String(localized: "medical.pdf.col.fastRises", defaultValue: "Subidas rápidas/día") }
    static var fastFalls: String { String(localized: "medical.pdf.col.fastFalls", defaultValue: "Bajadas rápidas/día") }
    static var daysColumn: String { String(localized: "medical.pdf.col.days", defaultValue: "Días") }

    static var weeklyTitle: String { String(localized: "medical.pdf.weekly.title", defaultValue: "Comparación semanal") }
    static func weeklySubtitle(_ previous: String, _ current: String) -> String {
        String(localized: "medical.pdf.weekly.subtitle", defaultValue: "Semana anterior: \(previous). Semana actual: \(current).")
    }
    static var measure: String { String(localized: "medical.pdf.weekly.measure", defaultValue: "Medida") }
    static var previousWeek: String { String(localized: "medical.pdf.weekly.previous", defaultValue: "Semana anterior") }
    static var currentWeek: String { String(localized: "medical.pdf.weekly.current", defaultValue: "Semana actual") }
    static var change: String { String(localized: "medical.pdf.weekly.change", defaultValue: "Cambio") }
    static var timeInRange: String { String(localized: "medical.pdf.weekly.timeInRange", defaultValue: "Tiempo en rango") }
    static var meals: String { String(localized: "medical.pdf.weekly.meals", defaultValue: "Comidas registradas") }
    static var exerciseMinutes: String {
        String(localized: "medical.pdf.weekly.exerciseMinutes", defaultValue: "Minutos de ejercicio")
    }

    static var dailyTitle: String { String(localized: "medical.pdf.daily.title", defaultValue: "Perfiles diarios") }
    static func dailySubtitle(_ unit: String) -> String {
        String(localized: "medical.pdf.daily.subtitle",
               defaultValue: "Curva de cada día, de 00 a 24 h (\(unit)); debajo, media y tiempo en el rango personal. Banda verde: rango objetivo.")
    }
    static var dailyNoData: String { String(localized: "medical.pdf.daily.noData", defaultValue: "Sin datos") }

    // MARK: Tablas opcionales

    static var mealsTitle: String { String(localized: "medical.pdf.meals.title", defaultValue: "Comidas") }
    static func mealsSubtitle(_ unit: String) -> String {
        String(localized: "medical.pdf.meals.subtitle",
               defaultValue: "Glucosa antes de comer (línea base), pico, subida y tiempo al pico en las 3 h siguientes (\(unit)). † = hubo otra comida en las 3 h previas. Los nutrientes son estimaciones.")
    }
    static var dateTime: String { String(localized: "medical.pdf.col.dateTime", defaultValue: "Fecha y hora") }
    static var meal: String { String(localized: "medical.pdf.meals.meal", defaultValue: "Comida") }
    static var mealDefault: String { String(localized: "medical.pdf.meals.default", defaultValue: "Comida") }
    static var carbs: String { String(localized: "medical.pdf.meals.carbs", defaultValue: "Carbs (g)") }
    static var protein: String { String(localized: "medical.pdf.meals.protein", defaultValue: "Prot. (g)") }
    static var fat: String { String(localized: "medical.pdf.meals.fat", defaultValue: "Grasa (g)") }
    static var kcal: String { String(localized: "medical.pdf.meals.kcal", defaultValue: "kcal") }
    static var before: String { String(localized: "medical.pdf.meals.before", defaultValue: "Antes") }
    static var peak: String { String(localized: "medical.pdf.meals.peak", defaultValue: "Pico") }
    static var rise: String { String(localized: "medical.pdf.meals.rise", defaultValue: "Subida") }
    static var timeToPeak: String { String(localized: "medical.pdf.meals.timeToPeak", defaultValue: "T. al pico") }

    static var nightsTitle: String {
        String(localized: "medical.pdf.nights.title", defaultValue: "Noches, sueño y actividad")
    }
    static func nightsSubtitle(_ unit: String) -> String {
        String(localized: "medical.pdf.nights.subtitle",
               defaultValue: "Glucosa en la ventana nocturna (\(unit)), sueño y pasos de Apple Salud. ‡ = la noche tiene menos del 70 % de lecturas.")
    }
    static var nightColumn: String { String(localized: "medical.pdf.nights.night", defaultValue: "Noche") }
    static var median: String { String(localized: "medical.pdf.nights.median", defaultValue: "Mediana") }
    static var minimum: String { String(localized: "medical.pdf.nights.min", defaultValue: "Mínima") }
    static var lowEpisodes: String { String(localized: "medical.pdf.nights.lowEpisodes", defaultValue: "Episodios bajos") }
    static var asleep: String { String(localized: "medical.pdf.nights.asleep", defaultValue: "Dormido") }
    static var awakenings: String { String(localized: "medical.pdf.nights.awakenings", defaultValue: "Despertares") }
    static var steps: String { String(localized: "medical.pdf.nights.steps", defaultValue: "Pasos") }
    static func averageSteps(_ steps: String) -> String {
        String(localized: "medical.pdf.nights.averageSteps", defaultValue: "Promedio de pasos por día con datos: \(steps).")
    }

    static var exerciseTitle: String { String(localized: "medical.pdf.exercise.title", defaultValue: "Ejercicio") }
    static func exerciseSubtitle(_ unit: String) -> String {
        String(localized: "medical.pdf.exercise.subtitle",
               defaultValue: "Cambio de la glucosa respecto a la media de los 15 min previos al inicio (\(unit)).")
    }
    static var exerciseType: String { String(localized: "medical.pdf.exercise.type", defaultValue: "Tipo") }
    static var exerciseDefault: String { String(localized: "medical.pdf.exercise.default", defaultValue: "Ejercicio") }
    static var duration: String { String(localized: "medical.pdf.exercise.duration", defaultValue: "Duración") }
    static var baseline: String { String(localized: "medical.pdf.exercise.baseline", defaultValue: "Previa") }
    static var atEnd: String { String(localized: "medical.pdf.exercise.atEnd", defaultValue: "Al terminar") }
    static var after60: String { String(localized: "medical.pdf.exercise.after60", defaultValue: "+60 min") }
    static var after120: String { String(localized: "medical.pdf.exercise.after120", defaultValue: "+120 min") }
    static var lowest: String { String(localized: "medical.pdf.exercise.lowest", defaultValue: "Mínimo") }

    static var bodyTitle: String { String(localized: "medical.pdf.body.title", defaultValue: "Composición corporal") }
    static var bodySubtitle: String {
        String(localized: "medical.pdf.body.subtitle",
               defaultValue: "Mediciones de la báscula registradas en Apple Salud durante el período. Solo cifras, sin valoración.")
    }
    static var bodyByDayTitle: String { String(localized: "medical.pdf.body.byDay", defaultValue: "Mediciones por día") }
    static var first: String { String(localized: "medical.pdf.body.first", defaultValue: "Primera") }
    static var last: String { String(localized: "medical.pdf.body.last", defaultValue: "Última") }
    static var measurements: String { String(localized: "medical.pdf.body.count", defaultValue: "Mediciones") }
    static var date: String { String(localized: "medical.pdf.body.date", defaultValue: "Fecha") }
    static var weightKg: String { String(localized: "medical.pdf.body.weight", defaultValue: "Peso (kg)") }
    static var bodyFat: String { String(localized: "medical.pdf.body.fat", defaultValue: "Grasa corporal (%)") }
    static var leanMass: String { String(localized: "medical.pdf.body.lean", defaultValue: "Masa magra (kg)") }
    static var bmiUnit: String { String(localized: "medical.pdf.body.bmi", defaultValue: "IMC (kg/m²)") }
    static var waist: String { String(localized: "medical.pdf.body.waist", defaultValue: "Cintura (cm)") }

    static var notesTitle: String { String(localized: "medical.pdf.notes.title", defaultValue: "Notas del diario") }
    static var notesSubtitle: String {
        String(localized: "medical.pdf.notes.subtitle", defaultValue: "Notas que la persona escribió en Lingclose durante el período.")
    }
    static var noteKind: String { String(localized: "medical.pdf.notes.kind", defaultValue: "Tipo") }
    static var note: String { String(localized: "medical.pdf.notes.note", defaultValue: "Nota") }
    static var sensorNote: String { String(localized: "medical.pdf.notes.sensorNote", defaultValue: "Nota del sensor") }
    static func moreNotes(_ count: Int) -> String {
        String(localized: "medical.pdf.notes.more", defaultValue: "… y \(count) notas más")
    }

    static var continued: String { String(localized: "medical.pdf.continued", defaultValue: "(continuación)") }

    // MARK: Notas y método

    static var methodTitle: String { String(localized: "medical.pdf.method.title", defaultValue: "Notas y método") }
    static var methodSource: String {
        String(localized: "medical.pdf.method.source",
               defaultValue: "Fuente de los datos: lecturas del biosensor de glucosa Abbott Lingo (plataforma FreeStyle Libre 3) recibidas por Lingclose. Lingclose no es un dispositivo médico y este reporte no sustituye el criterio de un profesional de salud ni un sistema médico. La persona no declara uso de insulina.")
    }
    static var methodRanges: String {
        String(localized: "medical.pdf.method.ranges",
               defaultValue: "Tiempo en rangos: cortes del consenso internacional de tiempo en rango (Battelino et al., 2019): <54, 54–69, 70–180, 181–250 y >250 mg/dL (3,0; 3,9; 10,0 y 13,9 mmol/L). Los porcentajes se calculan sobre la serie remuestreada a 5 min (15 min en períodos de más de 31 días). Las horas y minutos por día son el porcentaje por 24 h.")
    }
    static var methodGMI: String {
        String(localized: "medical.pdf.method.gmi",
               defaultValue: "GMI (indicador de gestión de glucosa) = 3,31 + 0,02392 × glucosa media (mg/dL). Es una estimación a partir de la media del sensor, no una HbA1c medida.")
    }
    static var methodCV: String {
        String(localized: "medical.pdf.method.cv",
               defaultValue: "Coeficiente de variación (CV) = desviación estándar ÷ glucosa media. La desviación estándar es muestral (n − 1).")
    }
    static var methodAGP: String {
        String(localized: "medical.pdf.method.agp",
               defaultValue: "AGP: mediana y percentiles 5, 25, 75 y 95 de las lecturas de cada media hora del día local durante todo el período; una media hora con lecturas de menos de 3 días no se dibuja. Cada valor de la tabla es el promedio de los percentiles de las medias horas de su franja de 2 horas.")
    }
    static var methodCoverage: String {
        String(localized: "medical.pdf.method.coverage",
               defaultValue: "Tiempo con sensor activo: minutos con al menos una lectura válida ÷ minutos del período. Un día cuenta como día con datos si tiene lectura en al menos el 50 % de sus minutos.")
    }
    static var methodOther: String {
        String(localized: "medical.pdf.method.other",
               defaultValue: "Comidas, ejercicio y notas son los que la persona registró en Lingclose; los nutrientes de las comidas son estimaciones. Sueño, pasos, peso y demás datos corporales vienen de Apple Salud (solo lectura). El rango personal y las franjas del día son orientativos y los fija la persona, no un médico.")
    }
}
