/// `resolution` de un conflicto (contrato §5.5 y §5.3). `lineage_unknown` viene de draft.4
/// (§5.3 "Falta algún eslabón necesario") y figura en `conflict.schema.json`.
public enum ConflictResolution: String, Sendable, Codable, Hashable, CaseIterable {
    case keptLocal = "kept_local"
    case tookRemote = "took_remote"
    case merged
    case divergent
    case aliased
    case policyDivergence = "policy_divergence"
    case lineageUnknown = "lineage_unknown"
}
