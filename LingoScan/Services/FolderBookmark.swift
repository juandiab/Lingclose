import Foundation

/// Dónde se guarda el bookmark de la carpeta elegida (contrato §3.2). En pruebas se sustituye por memoria.
protocol FolderBookmarkStoring: Sendable {
    func load() -> Data?
    func save(_ data: Data?)
}

/// Bookmark en `UserDefaults`: no es un secreto (solo apunta a una carpeta) y sobrevive a reinicios.
struct UserDefaultsFolderBookmarkStore: FolderBookmarkStoring {
    static let defaultKey = "com.otalvaro.lingoscan.archive.folderBookmark"
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> Data? { defaults.data(forKey: key) }

    func save(_ data: Data?) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// Carpeta elegida con el selector del sistema, persistida como bookmark con alcance de seguridad.
/// Si el bookmark caduca o deja de resolverse hay que pedir la carpeta de nuevo (la UI lo indica).
enum FolderBookmark {
    struct Resolved: Sendable, Equatable {
        let url: URL
        /// El sistema pide regenerar el bookmark; si se puede, `refreshedData` ya lo trae.
        let isStale: Bool
        let refreshedData: Data?
    }

    enum Failure: Error, Sendable, Equatable {
        case cannotCreate(String)
        case cannotResolve(String)
        case notAFolder
    }

    /// Crea el bookmark de una carpeta devuelta por el selector. Debe llamarse con el acceso abierto
    /// (`SecurityScopedAccess.run`), porque el selector solo concede el permiso mientras dura.
    static func make(from url: URL) throws -> Data {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.notAFolder
        }
        do { return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw Failure.cannotCreate(error.localizedDescription) }
    }

    /// Resuelve un bookmark guardado. Un bookmark caduco se regenera si la carpeta sigue accesible.
    static func resolve(_ data: Data) throws -> Resolved {
        var stale = false
        let url: URL
        do { url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw Failure.cannotResolve(error.localizedDescription) }
        guard stale else { return Resolved(url: url, isStale: false, refreshedData: nil) }
        let refreshed = try? SecurityScopedAccess.run(url) { try make(from: url) }
        return Resolved(url: url, isStale: true, refreshedData: refreshed)
    }
}

/// `startAccessingSecurityScopedResource` / `stop…` emparejados. Para URLs sin alcance (el contenedor propio)
/// el sistema devuelve `false` y el cuerpo se ejecuta igualmente.
enum SecurityScopedAccess {
    static func run<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Variante asíncrona: el cuerpo se ejecuta en el aislamiento de quien llama, con el alcance abierto todo el rato.
    static func run<T>(_ url: URL, isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> T) async rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try await body()
    }
}
