/// Se invoca tras persistir `prepared`, `response_saved` y `authenticated`
/// (`RECUPERACION_V1.md` §4). T-19 lo sustituye por la exportación cifrada.
protocol RecoveryExportHook: Sendable {
    func recoveryCheckpoint(_ record: ActivationRecord) async
}
