import Foundation

/// Política de elegibilidad que el importador aplica a los registros ajenos (contrato §6 y §8.4).
/// La de esta app es `lingoscan-v1`; el protocolo existe para que las pruebas ejerciten el lado de la
/// otra app (`astra-v1`, con otro rango) con el mismo importador.
public protocol ArchiveEligibilityPolicy: Sendable {
    var policyID: String { get }
    var policyVersion: String { get }
    func evaluate(raw: RawReading, lifeCount: Int, warmupMinutes: Int, synthetic: Bool, deleted: Bool,
                  inSyntheticPackage: Bool) -> Eligibility
    func value(for raw: RawReading, eligibility: Eligibility) -> Int?
}

/// `lingoscan-v1` (`LingoScanV1Policy`).
public struct LingoScanV1ArchivePolicy: ArchiveEligibilityPolicy {
    public init() {}
    public var policyID: String { LingoScanV1Policy.policyID }
    public var policyVersion: String { LingoScanV1Policy.policyVersion }

    public func evaluate(raw: RawReading, lifeCount: Int, warmupMinutes: Int, synthetic: Bool, deleted: Bool,
                         inSyntheticPackage: Bool) -> Eligibility {
        LingoScanV1Policy.evaluate(raw: raw, lifeCount: lifeCount, warmupMinutes: warmupMinutes,
                                   synthetic: synthetic, deleted: deleted, inSyntheticPackage: inSyntheticPackage)
    }

    public func value(for raw: RawReading, eligibility: Eligibility) -> Int? {
        LingoScanV1Policy.value(for: raw, eligibility: eligibility)
    }
}
