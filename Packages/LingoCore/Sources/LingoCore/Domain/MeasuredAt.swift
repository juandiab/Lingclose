/// Regla única de hora de medición (contrato §5.2): `activation_time_epoch_s + 60 · life_count`.
/// La corrección de reloj de Juggluco (si `now - esperado > 15 s`, manda el esperado) la aplica
/// quien recibe la trama; aquí solo vive la fórmula recomendada, determinista y sin reloj.
public enum MeasuredAt {
    public static func compute(activationEpoch: Int64, lifeCount: Int) -> UTCInstant {
        UTCInstant(epochSeconds: activationEpoch + 60 * Int64(lifeCount))
    }
}
