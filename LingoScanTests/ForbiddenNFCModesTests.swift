import Foundation
import Testing

/// Ningún archivo de `LingoScan/Services` puede usar los modos NFC de cambio de receptor o de
/// comando forzado del fork, y `.activateFreshSensor` solo vive en `NFCService.swift`.
struct ForbiddenNFCModesTests {
    private static let servicesDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "LingoScan/Services")

    private func sources() throws -> [(name: String, text: String)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.servicesDirectory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".swift") }
        return try names.map { ($0, try String(contentsOf: Self.servicesDirectory.appending(path: $0), encoding: .utf8)) }
    }

    @Test func servicesNeverUseSwitchOrForcedNFCModes() throws {
        let files = try sources()
        #expect(files.count > 10)
        let forbidden = ["." + "activateOrSwitchReceiver", "." + "switchReceiver", "." + "forceActivationCommand"]
        for file in files {
            for token in forbidden {
                #expect(!file.text.contains(token), "\(file.name) usa \(token)")
            }
        }
    }

    @Test func freshActivationOnlyInNFCService() throws {
        let users = try sources().filter { $0.text.contains("." + "activateFreshSensor") }.map(\.name)
        #expect(users == ["NFCService.swift"])
    }
}
