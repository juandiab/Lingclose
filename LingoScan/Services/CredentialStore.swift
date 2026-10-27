import Foundation
import RoundWhiteDiscKit

/// Importa, valida y custodia el JSON de identidad de app (Keychain) y lo
/// instala en `AppIdentities` para el pairing. Nunca registra ni describe
/// bytes de clave, certificado o JSON.
actor CredentialStore {
    static let service = "com.otalvaro.lingoscan.identity"
    static let account = "identity-json"

    private let keychain: KeychainItem

    init(keychain: KeychainItem = KeychainItem(service: CredentialStore.service, account: CredentialStore.account)) {
        self.keychain = keychain
    }

    /// Carga la identidad guardada (si hay) e instala. Devuelve si había una.
    @discardableResult
    func loadFromKeychain() throws -> Bool {
        guard let json = try keychain.read() else { return false }
        try Self.install(json)
        return true
    }

    /// Importa desde una URL elegida por el usuario (`fileImporter`/`onOpenURL`).
    /// Copia a un temporal propio, valida, guarda y borra solo esa copia; el
    /// archivo de origen no se toca.
    func importIdentity(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lingo-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temp) }

        let json: Data
        do {
            try FileManager.default.copyItem(at: url, to: temp)
            json = try Data(contentsOf: temp)
        } catch {
            throw CredentialImportError.unreadableSource
        }
        try importIdentity(json: json)
    }

    /// Valida e instala el JSON; solo si es válido lo guarda (reemplaza).
    func importIdentity(json: Data) throws {
        let previous = try? AppIdentities.installed()
        do {
            try Self.install(json)
            try keychain.save(json)
        } catch {
            if let previous { AppIdentities.install(previous) }
            throw error
        }
    }

    func identity(for family: SensorFamily) throws -> AppIdentity {
        let installed: [AppIdentity]
        do { installed = try AppIdentities.installed() } catch {
            throw CredentialImportError.noIdentity(family: family.rawValue)
        }
        guard let found = AppIdentities.identity(for: family, in: installed) else {
            throw CredentialImportError.noIdentity(family: family.rawValue)
        }
        return found
    }

    /// Nunca devuelve una lista vacía.
    func signingKeys(for family: SensorFamily) throws -> [Data] {
        let installed = (try? AppIdentities.installed()) ?? []
        let keys = PatchSigningKeys.keys(for: family, identities: installed)
        guard !keys.isEmpty else {
            throw CredentialImportError.noSigningKeys(family: family.rawValue)
        }
        return keys
    }

    /// Borra la identidad del Keychain (no toca archivos del usuario).
    func removeStoredIdentity() throws {
        try keychain.delete()
    }

    private static func install(_ json: Data) throws {
        do {
            try AppIdentities.install(json: json)
        } catch let error as AppIdentityError {
            throw map(error)
        } catch is DecodingError {
            throw CredentialImportError.invalidJSON
        } catch is PhoneCertError {
            throw CredentialImportError.invalidCertificate
        } catch {
            throw CredentialImportError.invalidPrivateKey
        }
    }

    private static func map(_ error: AppIdentityError) -> CredentialImportError {
        switch error {
        case .notInstalled: .noIdentities
        case .unsupportedFormat: .unsupportedFormat
        case .badHex: .invalidHex(field: "privateKeyHex/certificateHex/patchSigningPublicKeyHex")
        case .keyCertificateMismatch: .keyCertificateMismatch
        case .invalidPatchSigningPublicKey: .invalidPatchSigningPublicKey
        case .invalidProductTypes: .invalidProductTypes
        case .invalidSecurityVersions: .invalidSecurityVersions
        }
    }
}
