import Foundation
import Testing

/// T-26: el catálogo `Localizable.xcstrings` debe tener es, en y pt-BR en todas las claves, con los mismos
/// especificadores de formato (`%lld`, `%@`, `%1$@`, …) en las tres lenguas.
struct LocalizationCatalogTests {
    private static let languages = ["es", "en", "pt-BR"]

    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LingoScan/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        let root = try #require(json as? [String: Any])
        return try #require(root["strings"] as? [String: [String: Any]])
    }

    /// Todas las cadenas de una localización: una sola o, con variantes plurales, una por categoría.
    private func values(_ localization: [String: Any]) -> [String: String] {
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return ["": value]
        }
        var out: [String: String] = [:]
        let variations = localization["variations"] as? [String: Any]
        let plural = variations?["plural"] as? [String: [String: Any]] ?? [:]
        for (category, entry) in plural {
            if let unit = entry["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                out[category] = value
            }
        }
        return out
    }

    private func states(_ localization: [String: Any]) -> [String] {
        if let unit = localization["stringUnit"] as? [String: Any] { return [unit["state"] as? String ?? ""] }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return plural.values.map { ($0["stringUnit"] as? [String: Any])?["state"] as? String ?? "" }
    }

    private func specifiers(_ text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[dDiuUxXfFeEgGcsS@]|%%"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    @Test func everyKeyHasAllLanguagesTranslated() throws {
        let strings = try catalog()
        #expect(strings.count > 700)
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                let localization = localizations[language] ?? [:]
                let texts = values(localization)
                #expect(!texts.isEmpty, "\(key) vacía en \(language)")
                #expect(texts.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                        "\(key) tiene texto vacío en \(language)")
                #expect(states(localization).allSatisfy { $0 == "translated" }, "\(key) no está translated en \(language)")
            }
        }
    }

    @Test func formatSpecifiersMatchAcrossLanguages() throws {
        for (key, entry) in try catalog() {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            let reference = values(localizations["en"] ?? [:])
            for language in ["es", "pt-BR"] {
                let other = values(localizations[language] ?? [:])
                #expect(Set(other.keys) == Set(reference.keys), "\(key): categorías plurales distintas en \(language)")
                for (category, text) in reference {
                    guard let translated = other[category] else { continue }
                    #expect(specifiers(text) == specifiers(translated),
                            "\(key) [\(category)]: especificadores distintos en \(language)")
                }
            }
        }
    }

    @Test func notificationTitlesFitInFortyCharacters() throws {
        // Los títulos de aviso llevan un número ("%lld"): se mide con tres dígitos.
        for (key, entry) in try catalog() where key.hasPrefix("alert.") && key.hasSuffix(".title") {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                let text = values(localizations[language] ?? [:])[""] ?? ""
                let rendered = text.replacingOccurrences(of: "%lld", with: "999")
                #expect(rendered.count <= 40, "\(key) en \(language) mide \(rendered.count)")
            }
        }
    }
}
