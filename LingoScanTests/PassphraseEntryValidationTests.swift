import Testing
@testable import LingoScan

struct PassphraseEntryValidationTests {
    @Test func elevenCharactersMissingOne() {
        let v = PassphraseEntryValidation(passphrase: "12345678901", confirmation: "12345678901", savedElsewhere: true)
        #expect(v.missingCharacters == 1)
        #expect(!v.canSubmit)
    }

    @Test func edgeWhitespaceIsTrimmedBeforeCounting() {
        let v = PassphraseEntryValidation(passphrase: "  doce-letras! ", confirmation: "doce-letras!", savedElsewhere: true)
        #expect(v.missingCharacters == 0)
        #expect(v.matches)
    }

    @Test func mismatchIsDetected() {
        let v = PassphraseEntryValidation(passphrase: "doce-letras!", confirmation: "doce-letras?", savedElsewhere: true)
        #expect(!v.matches)
        #expect(!v.canSubmit)
    }

    @Test func matchingWithoutSavedElsewhereCannotSubmit() {
        let v = PassphraseEntryValidation(passphrase: "doce-letras!", confirmation: "doce-letras!", savedElsewhere: false)
        #expect(v.matches)
        #expect(!v.canSubmit)
    }

    @Test func allConditionsMetCanSubmit() {
        let v = PassphraseEntryValidation(passphrase: "doce-letras!", confirmation: "doce-letras!", savedElsewhere: true)
        #expect(v.canSubmit)
    }

    @Test func emptyStringsDoNotMatch() {
        let v = PassphraseEntryValidation(passphrase: "", confirmation: "", savedElsewhere: true)
        #expect(!v.matches)
        #expect(v.missingCharacters == 12)
        #expect(!v.canSubmit)
    }
}
