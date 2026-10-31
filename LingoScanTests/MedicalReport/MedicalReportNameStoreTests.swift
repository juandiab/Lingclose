import Foundation
import Testing
@testable import LingoScan

/// T-34: el nombre del paciente se guarda solo en el dispositivo, con clave versionada y normalizado.
struct MedicalReportNameStoreTests {
    private func suite() -> (UserDefaults, String) {
        let name = "t34-name-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func usesTheVersionedKey() {
        #expect(MedicalReportNameStore.key == "lingoscan.report.patient_name.v1")
    }

    @Test func savesNormalizedNameAndRemovesItWhenEmpty() {
        let (defaults, suiteName) = suite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MedicalReportNameStore(defaults: defaults)
        #expect(store.name.isEmpty)
        store.name = "  Ana   María\nPérez  "
        #expect(store.name == "Ana María Pérez")
        #expect(defaults.string(forKey: MedicalReportNameStore.key) == "Ana María Pérez")
        // Es lo único que se guarda en el almacén.
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("lingoscan") } == [MedicalReportNameStore.key])
        store.name = "   "
        #expect(defaults.object(forKey: MedicalReportNameStore.key) == nil)
    }

    @Test func limitsLengthToOneShortLine() {
        let long = String(repeating: "ñ", count: 300)
        #expect(MedicalReportNameStore.normalized(long).count == MedicalReportNameStore.maxLength)
        #expect(!MedicalReportNameStore.normalized("a\nb\tc").contains("\n"))
    }

    @Test func aSecondStoreOnTheSameDefaultsSeesTheName() {
        let (defaults, suiteName) = suite()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        MedicalReportNameStore(defaults: defaults).name = "Carlos"
        #expect(MedicalReportNameStore(defaults: defaults).name == "Carlos")
    }
}
