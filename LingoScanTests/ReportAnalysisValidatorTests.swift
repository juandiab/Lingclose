import Testing
@testable import LingoScan

/// El validador rechaza diagnósticos, enfermedades, insulina, medicación y dosis en es/en/pt, y deja pasar texto de hábitos.
struct ReportAnalysisValidatorTests {
    @Test(arguments: [
        "Ajusta la insulina antes de cenar.", "Tu Insulina sube.", "Take your insulin later.", "A insulina baixa.",
        "Esto parece diabetes.", "Possible Diabetic pattern.", "Sinais de prediabetes.", "Riesgo de hipoglucemia nocturna.",
        "Nocturnal hypoglycemia is likely.", "Episódios de hiperglicemia.", "Podría ser síndrome metabólico.",
        "Sounds like a metabolic syndrome.", "Esta enfermedad es común.", "A chronic disease.", "Uma doença crônica.",
        "Toma metformina con la cena.", "Consider medication.", "Revisa tu medicación.", "Tome o medicamento.",
        "Una dosis menor ayuda.", "Adjust the dose.", "A dosagem correta.", "Toma una pastilla.", "Take a pill.",
        "Pregunta por un fármaco.", "Ask about the drug.", "Use ozempic.", "Diabetes gestacional.",
    ])
    func rejects(text: String) {
        #expect(ReportAnalysisValidator.violation(in: [text]) != nil, "debería rechazar: \(text)")
    }

    @Test(arguments: [
        "Esto es una guía informativa y no consejo médico.", "This is a wellness guide, not medical advice.",
        "Isso é um guia informativo, não conselho médico.", "Camina diez minutos después de cenar.",
        "Usa una almohada cómoda; pillow talk no cuenta.", "Tu glucosa estuvo en rango el 91 % del tiempo.",
        "La mediana sube entre las 16:00 y las 18:00.", "Prueba cenar más temprano y compara.",
        "Hydrate and sleep well.", "Observe se a subida se repete.",
    ])
    func accepts(text: String) {
        #expect(ReportAnalysisValidator.violation(in: [text]) == nil, "no debería rechazar: \(text)")
    }

    @Test func looksAtEveryFieldOfTheReply() {
        var object = ReportAnalysisFixtures.replyObject()
        object["questions_to_explore"] = ["¿Cuánta insulina?"]
        let reply = try! ReportAnalysisParser.parse(object: object)
        #expect(ReportAnalysisValidator.violation(in: reply)?.term == "insulin")
        #expect(ReportAnalysisValidator.violation(in: try! ReportAnalysisParser.parse(object: ReportAnalysisFixtures.replyObject())) == nil)
    }
}
