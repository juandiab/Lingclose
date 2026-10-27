/// Política de referencia `lingoscan-v1` (contrato §6, matriz de `DATOS_Y_HEALTHKIT.md`). Función pura.
public enum LingoScanV1Policy {
    public static let policyID = "lingoscan-v1"
    public static let policyVersion = "1.0.0"
    /// Rango de almacenamiento de Juggluco (`validglucosevalue`); sin recortar a 39/501.
    public static let validRange = 39...501

    /// Evalúa una lectura. Varias razones → gana la de mayor precedencia del contrato §5.2
    /// (`deleted > synthetic > quality_flag > warm_up > out_of_range > decoder_error > duplicate > other`).
    ///
    /// - Parameters:
    ///   - synthetic: el registro es sintético.
    ///   - inSyntheticPackage: el contexto es un paquete `manifest.synthetic: true` (contrato §6). Ahí la
    ///     elegibilidad se calcula como si el dato fuera real y `synthetic` queda solo como barrera
    ///     estructural (`HealthExportable`). En la base real de la app (por defecto) un registro sintético
    ///     se marca `excluded / synthetic` para que ni la gráfica ni los reportes lo mezclen.
    public static func evaluate(
        raw: RawReading,
        lifeCount: Int,
        warmupMinutes: Int,
        synthetic: Bool,
        deleted: Bool,
        inSyntheticPackage: Bool = false
    ) -> Eligibility {
        var reasons: [ExclusionReason] = []
        if deleted { reasons.append(.deleted) }
        if synthetic && !inSyntheticPackage { reasons.append(.synthetic) }
        if raw.qualityFlag { reasons.append(.qualityFlag) }
        if lifeCount < warmupMinutes { reasons.append(.warmUp) }
        if let v = candidateValue(raw) {
            if !validRange.contains(v) { reasons.append(.outOfRange) }
        } else if !raw.qualityFlag {
            // Ni `uncapped` ni `capped` y sin bit 15: el decodificador no produjo valor.
            reasons.append(.decoderError)
        }
        guard let top = reasons.max(by: { $0.precedence < $1.precedence }) else {
            return .eligible(policyID: policyID, policyVersion: policyVersion)
        }
        return .excluded(top, policyID: policyID, policyVersion: policyVersion)
    }

    /// `uncapped` si existe; si no, `capped` (contrato §6).
    public static func candidateValue(_ raw: RawReading) -> Int? {
        raw.uncapped ?? raw.capped
    }

    /// `value` del contrato: el candidato si la lectura es elegible; `nil` si no.
    public static func value(for raw: RawReading, eligibility: Eligibility) -> Int? {
        eligibility.isEligible ? candidateValue(raw) : nil
    }
}
