/// Qué hizo `SQLiteStore.upsertEvent` según el linaje de ediciones (contrato §5.3, C3).
public enum EventUpsertOutcome: Sendable, Hashable {
    case inserted
    /// Mismo `edit_id`.
    case unchanged
    /// La nueva edición desciende de la guardada: pasa a ser la actual.
    case tookDescendant
    /// La guardada desciende de la nueva: se conserva.
    case keptNewerLocal
    /// Ramas divergentes con cadenas completas: se conserva la local, la otra va a `conflicts` (`divergent`).
    case divergent
    /// Falta un eslabón: se conservan ambas en `conflicts` (`lineage_unknown`), sin afirmar divergencia.
    case lineageUnknown
}
