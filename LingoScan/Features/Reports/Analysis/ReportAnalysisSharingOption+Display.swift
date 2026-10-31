import Foundation

/// Textos de cada interruptor del contexto opcional (T-33), para personas sin conocimientos técnicos.
extension ReportAnalysisSharingOption {
    var title: String {
        switch self {
        case .meals:
            String(localized: "reports.analysis.sharing.meals.title", defaultValue: "Comidas con nombre")
        case .sleepActivity:
            String(localized: "reports.analysis.sharing.sleep.title", defaultValue: "Sueño y pasos (Apple Salud)")
        case .profile:
            String(localized: "reports.analysis.sharing.profile.title", defaultValue: "Perfil y composición corporal (Apple Salud)")
        }
    }

    var explanation: String {
        switch self {
        case .meals:
            String(localized: "reports.analysis.sharing.meals.detail",
                   defaultValue: "Envía el nombre que escribiste o que el asistente reconoció y sus calorías, carbohidratos, proteínas y grasas, para que la IA relacione cada comida con su subida.")
        case .sleepActivity:
            String(localized: "reports.analysis.sharing.sleep.detail",
                   defaultValue: "Envía por noche a qué hora te acostaste y te levantaste, cuánto dormiste y los pasos de cada día. Lingclose solo lee; nunca escribe sueño ni pasos.")
        case .profile:
            String(localized: "reports.analysis.sharing.profile.detail",
                   defaultValue: "Edad, sexo, peso, altura y, si tu báscula los guarda en Salud, grasa corporal, masa magra y cintura con su cambio en el período. Solo como contexto general: la IA nunca juzga tu peso.")
        }
    }

    /// Lo que añade a la frase de privacidad de "Qué se enviará".
    var privacyItem: String {
        switch self {
        case .meals:
            String(localized: "reports.analysis.sharing.meals.item", defaultValue: "el nombre y los nutrientes de tus comidas")
        case .sleepActivity:
            String(localized: "reports.analysis.sharing.sleep.item", defaultValue: "tu sueño y tus pasos de Apple Salud")
        case .profile:
            String(localized: "reports.analysis.sharing.profile.item", defaultValue: "tu perfil y tu composición corporal de Apple Salud")
        }
    }

    static var commonFooter: String {
        String(localized: "reports.analysis.sharing.footer",
               defaultValue: "Todo es opcional. Lo apagado no sale del iPhone. Nunca se envían fotos, notas, identificadores ni tu nombre.")
    }
}
