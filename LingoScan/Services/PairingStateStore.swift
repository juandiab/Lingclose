import Foundation

/// Persistencia real del pairing (`ARQUITECTURA.md` §6):
/// - secretos en Keychain, un ítem por campo y sesión (`<session_id>.<campo>`),
///   `AfterFirstUnlockThisDeviceOnly`, sin iCloud (`KeychainItem`);
/// - lo no secreto en `pairing-state-<session_id>.json` dentro de Application Support.
actor PairingStateStore: PairingStatePersisting {
    static let keychainService = "com.otalvaro.lingoscan.pairing"

    nonisolated let recoveryHook: any RecoveryExportHook
    private let directory: URL
    private let keychainService: String
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(
        directory: URL = .applicationSupportDirectory,
        keychainService: String = PairingStateStore.keychainService,
        recoveryHook: any RecoveryExportHook
    ) {
        self.directory = directory
        self.keychainService = keychainService
        self.recoveryHook = recoveryHook
    }

    // MARK: - No secretos

    func currentSessionID() throws -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        var best: (id: String, at: Date)?
        for name in names where name.hasPrefix("pairing-state-") && name.hasSuffix(".json") {
            let id = String(name.dropFirst("pairing-state-".count).dropLast(".json".count))
            guard let state = try loadState(sessionID: id) else { continue }
            if best == nil || state.activation.updatedAt > (best?.at ?? .distantPast) {
                best = (id, state.activation.updatedAt)
            }
        }
        return best?.id
    }

    func loadState(sessionID: String) throws -> PairingState? {
        let url = fileURL(sessionID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try decoder.decode(PairingState.self, from: Data(contentsOf: url))
    }

    func saveState(_ state: PairingState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: fileURL(state.sessionID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Secretos

    func loadSecrets(sessionID: String) throws -> PairingSecrets {
        var secrets = PairingSecrets()
        secrets.receiverID = try text(sessionID, .receiverID).flatMap { UInt32($0) }
        secrets.pin = try text(sessionID, .pin).flatMap { Data(lowercaseHex: $0) }
        secrets.kAuth = try text(sessionID, .kAuth).flatMap { Data(lowercaseHex: $0) }
        secrets.bleAddress = try text(sessionID, .bleAddress)
        secrets.activationResponse = try text(sessionID, .activationResponse).flatMap { Data(lowercaseHex: $0) }
        secrets.serial = try text(sessionID, .serial)
        return secrets
    }

    func saveSecrets(_ secrets: PairingSecrets, sessionID: String) throws {
        if let v = secrets.receiverID { try save(String(v), sessionID, .receiverID) }
        if let v = secrets.pin { try save(v.lowercaseHex, sessionID, .pin) }
        if let v = secrets.kAuth { try save(v.lowercaseHex, sessionID, .kAuth) }
        if let v = secrets.bleAddress { try save(v, sessionID, .bleAddress) }
        if let v = secrets.activationResponse { try save(v.lowercaseHex, sessionID, .activationResponse) }
        if let v = secrets.serial { try save(v, sessionID, .serial) }
    }

    /// Borra JSON y secretos de una sesión. Solo para tests y para una acción explícita del usuario.
    func remove(sessionID: String) throws {
        for field in SecretField.allCases { try item(sessionID, field).delete() }
        try? FileManager.default.removeItem(at: fileURL(sessionID))
    }

    // MARK: - Privado

    private enum SecretField: String, CaseIterable {
        case receiverID = "receiver_id"
        case pin = "pin_hex"
        case kAuth = "k_auth_hex"
        case bleAddress = "ble_address"
        case activationResponse = "activation_response_hex"
        case serial = "sensor_serial"
    }

    private func fileURL(_ sessionID: String) -> URL {
        directory.appending(path: "pairing-state-\(sessionID).json")
    }

    private func item(_ sessionID: String, _ field: SecretField) -> KeychainItem {
        KeychainItem(service: keychainService, account: "\(sessionID).\(field.rawValue)")
    }

    private func text(_ sessionID: String, _ field: SecretField) throws -> String? {
        try item(sessionID, field).read().map { String(decoding: $0, as: UTF8.self) }
    }

    private func save(_ value: String, _ sessionID: String, _ field: SecretField) throws {
        try item(sessionID, field).save(Data(value.utf8))
    }
}
