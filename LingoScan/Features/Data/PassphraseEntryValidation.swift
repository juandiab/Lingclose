import LingoCore

/// Reglas de la hoja de frase de recuperación; la vista solo las muestra.
struct PassphraseEntryValidation: Equatable, Sendable {
    let passphrase: String
    let confirmation: String
    let savedElsewhere: Bool

    init(passphrase: String, confirmation: String, savedElsewhere: Bool) {
        self.passphrase = passphrase
        self.confirmation = confirmation
        self.savedElsewhere = savedElsewhere
    }

    /// Caracteres que faltan hasta el mínimo del servicio, sobre la frase normalizada.
    var missingCharacters: Int {
        max(0, RecoveryService.minimumPassphraseLength - RecoveryPassphrase.normalized(passphrase).count)
    }

    /// Ambas normalizadas son iguales y no vacías.
    var matches: Bool {
        let first = RecoveryPassphrase.normalized(passphrase)
        return !first.isEmpty && first == RecoveryPassphrase.normalized(confirmation)
    }

    var canSubmit: Bool {
        matches && missingCharacters == 0 && savedElsewhere
    }
}
