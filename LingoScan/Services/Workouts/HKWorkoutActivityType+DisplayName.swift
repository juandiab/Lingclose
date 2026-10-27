import HealthKit

extension HKWorkoutActivityType {
    /// Nombre legible del tipo de actividad; los no listados quedan como "Entrenamiento".
    var displayName: String {
        switch self {
        case .running: String(localized: "workout.activity.running", defaultValue: "Correr")
        case .walking: String(localized: "workout.activity.walking", defaultValue: "Caminar")
        case .hiking: String(localized: "workout.activity.hiking", defaultValue: "Senderismo")
        case .cycling: String(localized: "workout.activity.cycling", defaultValue: "Ciclismo")
        case .swimming: String(localized: "workout.activity.swimming", defaultValue: "Natación")
        case .elliptical: String(localized: "workout.activity.elliptical", defaultValue: "Elíptica")
        case .rowing: String(localized: "workout.activity.rowing", defaultValue: "Remo")
        case .stairClimbing, .stairs: String(localized: "workout.activity.stairs", defaultValue: "Escaleras")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            String(localized: "workout.activity.strength", defaultValue: "Fuerza")
        case .highIntensityIntervalTraining: String(localized: "workout.activity.hiit", defaultValue: "HIIT")
        case .crossTraining: String(localized: "workout.activity.crossTraining", defaultValue: "Entrenamiento cruzado")
        case .coreTraining: String(localized: "workout.activity.core", defaultValue: "Core")
        case .yoga: String(localized: "workout.activity.yoga", defaultValue: "Yoga")
        case .pilates: String(localized: "workout.activity.pilates", defaultValue: "Pilates")
        case .dance, .cardioDance, .socialDance: String(localized: "workout.activity.dance", defaultValue: "Baile")
        case .soccer: String(localized: "workout.activity.soccer", defaultValue: "Fútbol")
        case .basketball: String(localized: "workout.activity.basketball", defaultValue: "Baloncesto")
        case .tennis: String(localized: "workout.activity.tennis", defaultValue: "Tenis")
        case .mixedCardio: String(localized: "workout.activity.cardio", defaultValue: "Cardio")
        case .cooldown: String(localized: "workout.activity.cooldown", defaultValue: "Enfriamiento")
        case .flexibility: String(localized: "workout.activity.flexibility", defaultValue: "Flexibilidad")
        default: String(localized: "workout.activity.other", defaultValue: "Entrenamiento")
        }
    }
}
