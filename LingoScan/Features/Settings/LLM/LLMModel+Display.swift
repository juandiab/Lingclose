import Foundation

extension LLMModel {
    var imageSupportText: String {
        switch imageSupport {
        case .confirmed: String(localized: "llm.images.yes", defaultValue: "Imágenes: Sí")
        case .none: String(localized: "llm.images.no", defaultValue: "Imágenes: No")
        case .unconfirmed: String(localized: "llm.images.unconfirmed", defaultValue: "Imágenes: No confirmado")
        }
    }

    /// "0,10 $ / 0,50 $ por millón de tokens (entrada / salida) · fuente: …" o "No publicado".
    var priceText: String {
        guard let pricing, pricing.inputUSDPerMTok != nil || pricing.outputUSDPerMTok != nil else {
            return String(localized: "llm.price.unpublished", defaultValue: "Precio: No publicado")
        }
        let input = Self.dollars(pricing.inputUSDPerMTok)
        let output = Self.dollars(pricing.outputUSDPerMTok)
        let source = pricing.source
        return String(
            localized: "llm.price.format",
            defaultValue: "Precio: \(input) / \(output) por millón de tokens (entrada / salida) · fuente: \(source)")
    }

    /// Dos decimales como mínimo y hasta cuatro, con coma decimal. `nil` → "—".
    static func dollars(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0"), let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 3 {
            text.removeLast()
        }
        return text.replacingOccurrences(of: ".", with: ",") + " $"
    }
}
