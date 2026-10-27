/// Qué hizo `SQLiteStore.insertReading` con una lectura.
public enum ReadingInsertOutcome: Sendable, Hashable {
    /// No existía: se guardó tal cual.
    case inserted
    /// Ya existía idéntica (mismo `raw` y mismo `origin` o de menor precedencia): nada cambió.
    case unchanged
    /// `raw` idéntico por una ruta de mayor precedencia: solo sube `origin` (los bytes son los mismos).
    case originUpgraded
    /// La nueva observación, de mayor precedencia, sustituye a la anterior (`revision + 1`, conflicto `merged`).
    case replaced
    /// Exclusión levantada por una ruta distinta (`revision + 1`, conflicto `merged`, contrato §5.2 C5).
    case exclusionLifted
    /// Se conservó la guardada; la nueva queda en `conflicts` (`kept_local`) como observación complementaria.
    case keptExisting
}
