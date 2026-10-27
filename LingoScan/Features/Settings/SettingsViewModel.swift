import Foundation
import Observation

/// Estado de Ajustes: permisos, diagnóstico privado e "Acerca de".
@MainActor
@Observable
final class SettingsViewModel {
    static let diagnosticsKey = "com.otalvaro.lingoscan.diagnostics.private"

    /// Unidad de glucosa. Fija en mg/dL por ahora (D-12).
    let glucoseUnit = "mg/dL"
    let about: AboutInfo

    private(set) var bluetooth: PermissionState
    private(set) var nfcAvailable: Bool
    private(set) var healthAuthorized = false

    /// Preferencia persistida en `UserDefaults`. Todavía no la consume ningún registro: queda reservada para el
    /// registro detallado de la Fase 3 (`EventLog` no expone hoy una bandera de nivel).
    var privateDiagnostics: Bool {
        didSet { defaults.set(privateDiagnostics, forKey: Self.diagnosticsKey) }
    }

    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let health: (any HealthControlling)?
    @ObservationIgnored nonisolated(unsafe) private let defaults: UserDefaults

    init(
        permissions: any PermissionsProviding = SystemPermissions(),
        health: (any HealthControlling)?,
        about: AboutInfo = AboutInfo(),
        defaults: UserDefaults = .standard
    ) {
        self.permissions = permissions
        self.health = health
        self.about = about
        self.defaults = defaults
        bluetooth = permissions.bluetooth
        nfcAvailable = permissions.nfcAvailable
        privateDiagnostics = defaults.bool(forKey: Self.diagnosticsKey)
    }

    func refreshPermissions() async {
        bluetooth = permissions.bluetooth
        nfcAvailable = permissions.nfcAvailable
        if let health { healthAuthorized = await health.snapshot().isAuthorized }
    }
}
