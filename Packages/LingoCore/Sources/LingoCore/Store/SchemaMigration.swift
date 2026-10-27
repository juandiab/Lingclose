/// Paso de migración: lleva la base de `version - 1` a `version`. Cada paso termina fijando
/// `PRAGMA user_version` dentro de su propio guion estático.
struct SchemaMigration: Sendable {
    let version: Int
    let apply: @Sendable (SQLiteConnection) throws -> Void
}
