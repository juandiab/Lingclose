import LingoCore
@testable import LingoScan

actor RecordingRecoveryHook: RecoveryExportHook {
    private(set) var states: [ActivationState] = []

    func recoveryCheckpoint(_ record: ActivationRecord) {
        states.append(record.state)
    }
}
