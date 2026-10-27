import Foundation
import LingoCore

/// Grafo de servicios reales, construido una sola vez al arrancar y pasado por parámetro.
/// Crear `RoundWhiteDiscSensorLink` aquí (dentro de `App.init`) hace que el
/// `CBCentralManager` con restauración exista antes de que iOS entregue `willRestoreState`.
@MainActor
final class AppEnvironment {
    let store: SQLiteStore
    let credentials: CredentialStore
    let pairingStore: PairingStateStore
    let link: RoundWhiteDiscSensorLink
    let nfc: NFCService
    let coordinator: SensorSessionCoordinator
    let sensorStatus: LiveSensorStatusSource
    let todayData: LiveTodayDataSource
    let sensorActions: LiveSensorActions
    let identityImport: IdentityImportModel
    /// Entrenamientos de Salud (T-21 §5, solo lectura).
    let workoutImport: WorkoutImportTrigger

    private var startTask: Task<Void, Never>?

    init(databaseURL: URL) throws {
        let store = try SQLiteStore(path: databaseURL.path(percentEncoded: false))
        let credentials = CredentialStore()
        // Hook real de T-19: exporta el archivo de recuperación en `prepared`, `response_saved` y
        // `authenticated`; sin frase en memoria encola y lo anuncia. El hook de solo log queda de respaldo.
        let pairingStore = PairingStateStore(
            recoveryHook: LiveRecoveryExportHook(fallback: EventLogRecoveryExportHook(store: store))
        )
        let link = RoundWhiteDiscSensorLink()
        let nfc = NFCService()
        let coordinator = SensorSessionCoordinator(
            link: link, nfc: nfc, pairingStore: pairingStore, credentials: credentials, store: store
        )
        self.store = store
        self.credentials = credentials
        self.pairingStore = pairingStore
        self.link = link
        self.nfc = nfc
        self.coordinator = coordinator
        self.sensorStatus = LiveSensorStatusSource(coordinator: coordinator, pairingStore: pairingStore)
        self.todayData = LiveTodayDataSource(store: store, coordinator: coordinator)
        self.sensorActions = LiveSensorActions(coordinator: coordinator, credentials: credentials, pairingStore: pairingStore)
        self.identityImport = IdentityImportModel(credentials: credentials)
        self.workoutImport = Self.makeWorkoutImport(store: store)
        workoutImport.install()
        installRecovery()
        // T-10: servicio de archivo portable, tarea diaria (BGAppRefreshTask) y limpieza de `.partial`.
        configureArchive(databaseURL: databaseURL)
    }

    /// Base en `Application Support/LingoScan/lingoscan.sqlite`. Se crea la carpeta y se deja
    /// incluida en el backup del dispositivo (no se marca `isExcludedFromBackup`).
    static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        var folder = URL.applicationSupportDirectory.appending(path: "LingoScan", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try folder.setResourceValues(values)
        return folder.appending(path: "lingoscan.sqlite", directoryHint: .notDirectory)
    }

    static func live() throws -> AppEnvironment {
        try AppEnvironment(databaseURL: defaultDatabaseURL())
    }

    /// Identidad desde el Keychain y restauración del coordinador (CoreBluetooth). Idempotente.
    func start() {
        guard startTask == nil else { return }
        let credentials = credentials
        let coordinator = coordinator
        let store = store
        startTask = Task {
            do {
                try await credentials.loadFromKeychain()
            } catch {
                try? await store.logEvent(.error, category: "credentials", "identidad del llavero no cargada: \(public: String(describing: type(of: error)))")
            }
            await coordinator.start()
            await identityImport.refresh()
        }
    }
}
