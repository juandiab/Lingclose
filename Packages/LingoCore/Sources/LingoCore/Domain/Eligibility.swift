/// Resultado de la política (`eligibility`, contrato §5.2): `reason == nil` si y solo si `status == .eligible`.
public struct Eligibility: Sendable, Hashable, Codable {
    public let status: EligibilityStatus
    public let reason: ExclusionReason?
    public let policyID: String
    public let policyVersion: String

    public static func eligible(policyID: String, policyVersion: String) -> Eligibility {
        Eligibility(status: .eligible, reason: nil, policyID: policyID, policyVersion: policyVersion)
    }

    public static func excluded(_ reason: ExclusionReason, policyID: String, policyVersion: String) -> Eligibility {
        Eligibility(status: .excluded, reason: reason, policyID: policyID, policyVersion: policyVersion)
    }

    public var isEligible: Bool { status == .eligible }

    private init(status: EligibilityStatus, reason: ExclusionReason?, policyID: String, policyVersion: String) {
        self.status = status
        self.reason = reason
        self.policyID = policyID
        self.policyVersion = policyVersion
    }

    enum CodingKeys: String, CodingKey {
        case status, reason
        case policyID = "policy_id"
        case policyVersion = "policy_version"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let status = try c.decode(EligibilityStatus.self, forKey: .status)
        let reason = try c.decodeIfPresent(ExclusionReason.self, forKey: .reason)
        guard (status == .eligible) == (reason == nil) else {
            throw DecodingError.dataCorruptedError(forKey: .reason, in: c, debugDescription: "reason nulo si y solo si status == eligible")
        }
        self.init(status: status, reason: reason,
                  policyID: try c.decode(String.self, forKey: .policyID),
                  policyVersion: try c.decode(String.self, forKey: .policyVersion))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(reason, forKey: .reason)
        try c.encode(policyID, forKey: .policyID)
        try c.encode(policyVersion, forKey: .policyVersion)
    }
}
