import Foundation

/// Juez del contenido de un análisis (T-27d, D-30; precedente D-27): rechaza **entera** la respuesta si en cualquier
/// texto aparece un diagnóstico o enfermedad como etiqueta, insulina, medicación o dosis, o un juicio sobre el peso
/// (T-33: sobrepeso, delgadez, bajo peso, perder peso…), en español, inglés o portugués. Compara sin mayúsculas ni
/// tildes y por palabras (no por subcadenas sueltas), de modo que "médico" en la nota "no es consejo médico",
/// "pillow" o "el peso de la cena" no disparan el rechazo.
enum ReportAnalysisValidator {
    struct Violation: Sendable, Equatable {
        /// La raíz o palabra prohibida que se encontró.
        var term: String
    }

    /// Raíces: basta con que una palabra del texto empiece así.
    static let forbiddenPrefixes = [
        // Enfermedades y etiquetas clínicas (es / en / pt)
        "diabet", "prediabet", "hipoglucem", "hiperglucem", "hipoglic", "hiperglic", "hypoglyc", "hyperglyc",
        "sindrome", "syndrome", "sindroma", "enfermedad", "disease", "doenca", "trastorno", "disorder", "transtorno",
        "cetoacidosis", "ketoacidosis", "cetoacidose", "gestacional", "gestational", "neuropat", "retinopat", "nefropat",
        "pancreatitis", "obesidad", "obesity", "obesidade",
        // Insulina y medicación
        "insulin", "medicacion", "medicament", "medication", "medicine", "farmaco", "pharmac", "metformin", "glucophage",
        "ozempic", "semaglutid", "tirzepatid", "sulfonilurea", "sulfonylurea", "prescri", "inyecci", "inyectar", "inject",
        "dosis", "dosage", "dosagem", "pastilla", "comprimido", "tableta",
        // Juicios sobre el peso (T-33): el IMC es solo contexto
        "sobrepeso", "overweight", "underweight", "delgadez", "magreza", "obes",
    ]

    /// Palabras completas (las raíces cortas darían falsos positivos, p. ej. "pill" en "pillow").
    static let forbiddenWords: Set<String> = [
        "pill", "pills", "dose", "doses", "drug", "drugs", "dosar", "droga", "drogas", "tablet", "tablets", "glp",
    ]

    /// Expresiones de varias palabras (ya sin tildes ni mayúsculas) que juzgan el peso (T-33). "Peso" a secas no se
    /// rechaza: "el peso de la cena" es aceptable.
    static let forbiddenPhrases = [
        "bajo peso", "exceso de peso", "excesso de peso", "baixo peso", "abaixo do peso",
        "perder peso", "bajar de peso", "perdida de peso", "perda de peso", "lose weight", "weight loss",
        // Grasa corporal juzgada o recomendación de perderla (adenda 1)
        "grasa corporal alta", "grasa corporal baja", "gordura corporal alta", "gordura corporal baixa",
        "high body fat", "low body fat", "body fat is high", "body fat is low",
        "perder grasa", "bajar grasa", "perder gordura", "lose fat", "ganar peso", "ganhar peso", "gain weight",
    ]

    /// `nil` si todo el texto es aceptable; si no, el primer término prohibido.
    static func violation(in texts: [String]) -> Violation? {
        for text in texts {
            let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            for word in words {
                if forbiddenWords.contains(word) { return Violation(term: word) }
                if let prefix = forbiddenPrefixes.first(where: word.hasPrefix) { return Violation(term: prefix) }
            }
            let joined = " " + words.joined(separator: " ") + " "
            if let phrase = forbiddenPhrases.first(where: { joined.contains(" \($0) ") }) { return Violation(term: phrase) }
        }
        return nil
    }

    static func violation(in reply: ReportAnalysisReply) -> Violation? {
        violation(in: reply.allTexts)
    }
}
