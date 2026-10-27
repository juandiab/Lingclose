import RoundWhiteDiscKit

extension CredentialStore {
    /// Etiquetas y familias de las identidades instaladas. Sin material criptográfico.
    func installedSummaries() -> [IdentitySummary] {
        let installed = (try? AppIdentities.installed()) ?? []
        return installed.map { identity in
            IdentitySummary(
                label: identity.label,
                families: [RWDKSensorFamily.lingo, .libre3].filter(identity.serves).map(\.rawValue)
            )
        }
    }

    /// `true` si hay claves de firma no vacías para Lingo.
    func hasLingoSigningKeys() -> Bool {
        (try? signingKeys(for: .lingo))?.isEmpty == false
    }
}
