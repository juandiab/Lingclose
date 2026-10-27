import Foundation

/// Nutrición de comidas (T-21 §3, tabla `meal_nutrition` de la migración v2). SQL literal estático y
/// parámetros ligados, como el resto de `SQLiteStore`. La tabla no se exporta al `.lingoscan`.
extension SQLiteStore {
    /// Inserta o reemplaza el registro de nutrición de un evento existente (clave foránea a `events`).
    public func upsertMealNutrition(_ record: MealNutritionRecord) throws {
        try Self.validate(record)
        try connection.transaction { try writeMealNutrition(record) }
    }

    /// Registro de nutrición del evento, o `nil` si no tiene (eventos `meal` antiguos o sin análisis).
    public func mealNutrition(eventID: String) throws -> MealNutritionRecord? {
        try connection.queryFirst("""
            SELECT event_id, source_json, kind, name, basis_json, base_json, multiplier, overrides_json, assumptions,
              confidence, analyzed_at_epoch_s, updated_at_epoch_s
            FROM meal_nutrition WHERE event_id = ?
            """, [SQLiteValue(eventID)]) { try decodeMealNutrition($0) }
    }

    /// Borra solo el registro de nutrición; el evento queda intacto.
    public func deleteMealNutrition(eventID: String) throws {
        try connection.transaction {
            try connection.run("DELETE FROM meal_nutrition WHERE event_id = ?", [SQLiteValue(eventID)])
        }
    }

    /// Guarda el evento `meal` y su nutrición en **una** transacción. El `carbs_g` del evento se fija a
    /// `nutrition.effectiveNutrients.carbsG` (desconocido → `NULL`, nunca 0). El evento pasa por
    /// `upsertEvent` (linaje de ediciones, C3); la fila solo se escribe si esa versión del evento queda como
    /// actual (`inserted`, `tookDescendant`, o `unchanged` con el mismo `carbs_g`), para que fila y evento no
    /// diverjan. Cada guardado debe llevar un `edit_id` nuevo, como cualquier edición.
    @discardableResult
    public func saveMeal(event: DiaryEvent, nutrition: MealNutritionRecord) throws -> EventUpsertOutcome {
        guard event.eventID == nutrition.eventID else {
            throw StoreError.invalidMealNutrition(eventID: event.eventID, reason: "event_id distinto en el registro")
        }
        guard event.kind == .meal else {
            throw StoreError.invalidMealNutrition(eventID: event.eventID, reason: "el evento no es meal")
        }
        try Self.validate(nutrition)
        var meal = event
        meal.carbsG = nutrition.effectiveNutrients.carbsG
        return try connection.transaction {
            let outcome = try upsertEvent(meal)
            switch outcome {
            case .inserted, .tookDescendant:
                try writeMealNutrition(nutrition)
            case .unchanged:
                if try self.event(id: meal.eventID)?.carbsG == meal.carbsG { try writeMealNutrition(nutrition) }
            case .keptNewerLocal, .divergent, .lineageUnknown:
                break
            }
            return outcome
        }
    }

    // MARK: - Privado

    private static func validate(_ r: MealNutritionRecord) throws {
        guard r.kind != .notFood else {
            throw StoreError.invalidMealNutrition(eventID: r.eventID, reason: "kind not_food")
        }
        guard r.multiplier.isFinite, NutrientLimits.portionMultiplier.contains(r.multiplier) else {
            throw StoreError.invalidMealNutrition(eventID: r.eventID, reason: "multiplicador fuera de 0,5…5,0")
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    private func writeMealNutrition(_ r: MealNutritionRecord) throws {
        let encoder = Self.makeEncoder()
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        try connection.run("""
            INSERT INTO meal_nutrition (event_id, source_json, kind, name, basis_json, base_json, multiplier, overrides_json,
              assumptions, confidence, analyzed_at_epoch_s, updated_at_epoch_s)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
              source_json = excluded.source_json, kind = excluded.kind, name = excluded.name,
              basis_json = excluded.basis_json, base_json = excluded.base_json, multiplier = excluded.multiplier,
              overrides_json = excluded.overrides_json, assumptions = excluded.assumptions,
              confidence = excluded.confidence, analyzed_at_epoch_s = excluded.analyzed_at_epoch_s,
              updated_at_epoch_s = excluded.updated_at_epoch_s
            """, [
                SQLiteValue(r.eventID), SQLiteValue(try json(r.source)), SQLiteValue(r.kind.rawValue), SQLiteValue(r.name),
                SQLiteValue(try json(r.basis)), SQLiteValue(try json(r.baseNutrients)), SQLiteValue(r.multiplier),
                SQLiteValue(try json(r.overrides)), SQLiteValue(r.assumptions), SQLiteValue(r.confidence),
                SQLiteValue(r.analyzedAt?.epochSeconds), SQLiteValue(r.updatedAt.epochSeconds),
            ])
    }

    private func decodeMealNutrition(_ s: SQLiteStatement) throws -> MealNutritionRecord {
        func required<T>(_ v: T?, _ column: String) throws -> T {
            guard let v else { throw StoreError.corruptRow(table: "meal_nutrition", detail: column) }
            return v
        }
        let decoder = JSONDecoder()
        func decoded<T: Decodable>(_ type: T.Type, _ index: Int32, _ column: String) throws -> T {
            try decoder.decode(type, from: Data(try required(s.text(index), column).utf8))
        }
        return MealNutritionRecord(
            eventID: try required(s.text(0), "event_id"),
            source: try decoded(MealNutritionSource.self, 1, "source_json"),
            kind: try required(s.text(2).flatMap(FoodAnalysisKind.init(rawValue:)), "kind"),
            name: s.text(3),
            basis: try decoded(PortionBasis.self, 4, "basis_json"),
            baseNutrients: try decoded(Nutrients.self, 5, "base_json"),
            multiplier: try required(s.double(6), "multiplier"),
            overrides: try decoded(Nutrients.self, 7, "overrides_json"),
            assumptions: s.text(8),
            confidence: s.double(9),
            analyzedAt: s.int64(10).map(UTCInstant.init(epochSeconds:)),
            updatedAt: UTCInstant(epochSeconds: try required(s.int64(11), "updated_at_epoch_s"))
        )
    }
}
