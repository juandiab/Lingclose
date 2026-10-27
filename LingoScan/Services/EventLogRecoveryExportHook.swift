import LingoCore

/// Implementación provisional: solo deja constancia en `event_log`.
struct EventLogRecoveryExportHook: RecoveryExportHook {
    let store: SQLiteStore

    func recoveryCheckpoint(_ record: ActivationRecord) async {
        try? await store.logEvent(
            .info, category: "recovery",
            "exportación de recuperación pendiente (T-19): estado \(public: record.state.rawValue), sequence \(record.sequence)"
        )
    }
}
