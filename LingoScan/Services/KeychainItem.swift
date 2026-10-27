import Foundation
import Security

/// Envoltorio mínimo sobre `SecItem*` para un único ítem genérico (servicio +
/// cuenta). Solo mueve `Data`; no registra ni describe su contenido.
struct KeychainItem: Sendable {
    let service: String
    let account: String
    /// `nil` usa el grupo por defecto de la app (sin depender del entitlement).
    let accessGroup: String?

    init(service: String, account: String, accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// Devuelve `nil` si no existe.
    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw CredentialImportError.keychain(status: status)
        }
    }

    /// Crea o reemplaza el valor, `AfterFirstUnlockThisDeviceOnly`, sin iCloud.
    func save(_ data: Data) throws {
        let update = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw CredentialImportError.keychain(status: status) }
        default:
            throw CredentialImportError.keychain(status: update)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialImportError.keychain(status: status)
        }
    }
}
