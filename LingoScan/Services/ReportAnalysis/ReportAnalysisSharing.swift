/// Qué contexto opcional puede ver la IA al analizar un reporte (T-33): tres interruptores independientes, apagados
/// por defecto. Lo apagado no sale del iPhone.
struct ReportAnalysisSharing: Sendable, Hashable {
    var meals = false
    var sleepActivity = false
    var profile = false

    static let none = ReportAnalysisSharing()

    /// Todo apagado: el mensaje es el de siempre.
    var isEmpty: Bool { !meals && !sleepActivity && !profile }

    /// Interruptores encendidos, en el orden de `ReportAnalysisSharingOption.allCases`.
    var enabled: [ReportAnalysisSharingOption] { ReportAnalysisSharingOption.allCases.filter(contains) }

    func contains(_ option: ReportAnalysisSharingOption) -> Bool {
        switch option {
        case .meals: meals
        case .sleepActivity: sleepActivity
        case .profile: profile
        }
    }

    /// Para enlazar cada `Toggle` con `$sharing[option]`.
    subscript(option: ReportAnalysisSharingOption) -> Bool {
        get { contains(option) }
        set { set(option, newValue) }
    }

    mutating func set(_ option: ReportAnalysisSharingOption, _ isOn: Bool) {
        switch option {
        case .meals: meals = isOn
        case .sleepActivity: sleepActivity = isOn
        case .profile: profile = isOn
        }
    }
}
