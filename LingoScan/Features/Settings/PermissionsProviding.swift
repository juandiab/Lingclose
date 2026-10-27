import CoreBluetooth
import CoreNFC

/// Estado de un permiso del sistema tal como lo muestra Ajustes.
enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case unavailable
}

/// Permisos que se leen sin pedirlos. Las pruebas inyectan un doble.
@MainActor
protocol PermissionsProviding {
    var bluetooth: PermissionState { get }
    var nfcAvailable: Bool { get }
}

struct SystemPermissions: PermissionsProviding {
    var bluetooth: PermissionState {
        switch CBCentralManager.authorization {
        case .allowedAlways: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    var nfcAvailable: Bool { NFCTagReaderSession.readingAvailable }
}
