import SwiftUI

/// Hoja para introducir la frase de recuperación: escritura, repetición, confirmación de copia
/// externa y destino (memoria o Llavero). Nada de la frase se registra ni se imprime.
struct PassphraseEntrySheet: View {
    @Bindable var model: RecoveryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var failed = false

    private var validation: PassphraseEntryValidation {
        PassphraseEntryValidation(passphrase: model.passphrase, confirmation: model.passphraseConfirmation,
                                  savedElsewhere: model.passphraseSavedElsewhere)
    }

    var body: some View {
        NavigationStack {
            Form {
                phraseSection
                beforeUsingSection
                keychainSection
                if failed, let message = model.message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                submitSection
            }
            .navigationTitle(String(localized: "recovery.sheet.title", defaultValue: "Frase de recuperación"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "recovery.sheet.cancel", defaultValue: "Cancelar")) { dismiss() }
                }
            }
            .disabled(model.isWorking)
        }
        .onDisappear { model.resetPassphraseEntry() }
    }

    private var phraseSection: some View {
        Section {
            HStack {
                phraseField
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(revealed
                    ? String(localized: "recovery.sheet.hide", defaultValue: "Ocultar frase")
                    : String(localized: "recovery.sheet.show", defaultValue: "Mostrar frase"))
            }
            confirmationField
        } header: {
            Text(String(localized: "recovery.sheet.phrase.header", defaultValue: "Frase"))
        } footer: {
            liveStatus
        }
    }

    @ViewBuilder
    private var phraseField: some View {
        let prompt = String(localized: "recovery.sheet.phrase.placeholder", defaultValue: "Escribe la frase (12 caracteres o más)")
        if revealed {
            TextField(prompt, text: $model.passphrase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            SecureField(prompt, text: $model.passphrase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var confirmationField: some View {
        let prompt = String(localized: "recovery.sheet.confirm.placeholder", defaultValue: "Repite la frase")
        if revealed {
            TextField(prompt, text: $model.passphraseConfirmation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            SecureField(prompt, text: $model.passphraseConfirmation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        if validation.missingCharacters > 0 {
            Text(String(format: String(localized: "recovery.sheet.missing", defaultValue: "Faltan %lld caracteres"), validation.missingCharacters))
        } else if model.passphraseConfirmation.isEmpty {
            Text(String(localized: "recovery.sheet.repeat", defaultValue: "Repite la frase para comprobarla"))
        } else if validation.matches {
            Label(String(localized: "recovery.sheet.match", defaultValue: "Las frases coinciden"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(String(localized: "recovery.sheet.mismatch", defaultValue: "Las frases no coinciden"))
        }
    }

    private var beforeUsingSection: some View {
        Section {
            Toggle(String(localized: "recovery.sheet.saved", defaultValue: "Ya guardé la frase fuera del teléfono"),
                   isOn: $model.passphraseSavedElsewhere)
        } header: {
            Text(String(localized: "recovery.sheet.before.header", defaultValue: "Antes de usarla"))
        } footer: {
            Text(String(localized: "recovery.sheet.before.footer", defaultValue: "Sin la frase no se pueden abrir los archivos de recuperación. LingoScan no puede recuperarla."))
        }
    }

    private var keychainSection: some View {
        Section {
            Toggle(String(localized: "recovery.passphrase.remember", defaultValue: "Recordar en el Llavero"),
                   isOn: $model.rememberPassphrase)
        } header: {
            Text(String(localized: "recovery.sheet.keychain.header", defaultValue: "Guardado en el iPhone"))
        } footer: {
            Text(model.rememberPassphrase
                ? String(localized: "recovery.sheet.keychain.on", defaultValue: "Se guarda en el Llavero de este iPhone, protegida por el código y Face ID, y no se sube a iCloud.")
                : String(localized: "recovery.sheet.keychain.off", defaultValue: "Se pide una vez por sesión de la app y se olvida al cerrarla."))
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task {
                    failed = false
                    await model.usePassphrase()
                    if model.passphraseAccepted {
                        dismiss()
                    } else {
                        failed = true
                    }
                }
            } label: {
                Text(String(localized: "recovery.passphrase.use", defaultValue: "Usar frase"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!validation.canSubmit)
        }
        .listRowBackground(Color.clear)
    }
}

#Preview {
    PassphraseEntrySheet(model: RecoveryViewModel(context: .resolve()))
}
