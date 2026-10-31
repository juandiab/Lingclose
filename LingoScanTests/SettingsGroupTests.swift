import Foundation
import Testing
@testable import LingoScan

/// T-31 (D-34): Ajustes se ordena por lo que importa al usuario y cada grupo tiene header y pie.
struct SettingsGroupTests {
    @Test func groupsFollowTheAgreedOrder() {
        #expect(SettingsGroup.allCases == [.readings, .personalization, .connections, .advanced, .about])
    }

    @Test func everyGroupHasAShortHeaderAndAPlainFooter() {
        for group in SettingsGroup.allCases {
            #expect(!group.title.isEmpty)
            #expect(group.title.count <= 20, "\(group) tiene un header largo")
            #expect(!group.footer.isEmpty)
            // Una o dos frases.
            let sentences = group.footer.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            #expect(sentences.count <= 2, "\(group): \(group.footer)")
        }
    }
}
