import Foundation

/// Claves de API de los proveedores, una por proveedor, en el Llavero (servicio
/// `com.otalvaro.lingoscan.llm`, cuenta = `LLMProviderID.rawValue`, `AfterFirstUnlockThisDeviceOnly`,
/// sin iCloud). La clave no se describe, no se registra y no va al `.lingoscan`.
actor LLMKeyStore {
    static let service = "com.otalvaro.lingoscan.llm"

    private let itemFor: @Sendable (LLMProviderID) -> any SecretItemStoring

    init(itemFor: @escaping @Sendable (LLMProviderID) -> any SecretItemStoring = LLMKeyStore.keychainItem) {
        self.itemFor = itemFor
    }

    @Sendable static func keychainItem(for provider: LLMProviderID) -> any SecretItemStoring {
        KeychainItem(service: service, account: provider.rawValue)
    }

    /// Guarda la clave sin espacios alrededor. Una clave vacía equivale a olvidarla.
    func save(_ key: String, for provider: LLMProviderID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(for: provider)
            return
        }
        try itemFor(provider).save(Data(trimmed.utf8))
    }

    /// `nil` si no hay clave guardada.
    func key(for provider: LLMProviderID) throws -> String? {
        guard let data = try itemFor(provider).read(), let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    func hasKey(for provider: LLMProviderID) -> Bool {
        ((try? key(for: provider)) ?? nil) != nil
    }

    func delete(for provider: LLMProviderID) throws {
        try itemFor(provider).delete()
    }
}
