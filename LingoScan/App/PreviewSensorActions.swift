import Foundation

/// Acciones de previsualización (`#Preview` y `-previewSensorState`). No tocan NFC ni BLE.
@MainActor
final class PreviewSensorActions: SensorActions {
    func readSensor() async throws {}

    func credentialBlocker() async -> ActivationBlocker? { nil }

    func prepareActivation() async throws -> ActivationSummary {
        ActivationSummary(
            family: .lingo,
            productType: 9,
            securityVersion: 3,
            serialRedacted: "SYN…01",
            warmupMinutes: PreviewData.warmupMinutes,
            wearMinutes: PreviewData.wearMinutes,
            receiverID: 0x1234_5678,
            preparedAt: .now
        )
    }

    func activate(_ confirmation: ActivationConfirmation) async throws {}
}
