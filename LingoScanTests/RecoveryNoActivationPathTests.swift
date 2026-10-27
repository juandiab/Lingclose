import Foundation
import Testing

/// "Conectar sensor activo" y la importación nunca llegan a la activación NFC (`0xA0`/`0xA8`).
struct RecoveryNoActivationPathTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test func connectActiveSensorViewNeverReferencesTheActivationTicket() throws {
        let view = try Self.text("LingoScan/Features/Sensor/ConnectActiveSensorView.swift")
        #expect(view.contains("struct ConnectActiveSensorView"))
        #expect(!view.contains("Activation" + "Ticket"))
    }

    @Test func recoveryFilesNeverReachActivation() throws {
        let files = [
            "LingoScan/Features/Sensor/ConnectActiveSensorView.swift",
            "LingoScan/Features/Data/RecoveryLiveSensorConnector.swift",
            "LingoScan/Features/Data/RecoveryActiveSensorConnecting.swift",
            "LingoScan/Features/Data/RecoveryView.swift",
            "LingoScan/Features/Data/RecoveryViewModel.swift",
            "LingoScan/Features/Data/RecoveryContext.swift",
            "LingoScan/Services/RecoveryService.swift",
            "LingoScan/Services/RecoveryExportHook+Live.swift",
            "LingoScan/App/AppEnvironment+Recovery.swift",
        ]
        let forbidden = ["Activation" + "Ticket", "prepare" + "Activation(", ".activate(", "activate" + "FreshSensor",
                         "switch" + "Receiver", "NFC" + "Service", "readPatch" + "Info", "Sensor" + "Link"]
        for file in files {
            let source = try Self.text(file)
            for token in forbidden {
                #expect(!source.contains(token), "\(file) contiene \(token)")
            }
        }
    }
}
