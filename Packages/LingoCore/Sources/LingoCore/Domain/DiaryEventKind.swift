/// `kind` de un evento del diario (contrato §5.3).
public enum DiaryEventKind: String, Sendable, Codable, Hashable, CaseIterable {
    case meal
    case exercise
    case note
    case sensorNote = "sensor_note"
}
