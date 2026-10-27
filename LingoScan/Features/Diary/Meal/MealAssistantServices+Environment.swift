import SwiftUI

private struct MealAssistantKey: EnvironmentKey {
    static let defaultValue = MealAssistantServices.preview
}

extension EnvironmentValues {
    var mealAssistant: MealAssistantServices {
        get { self[MealAssistantKey.self] }
        set { self[MealAssistantKey.self] = newValue }
    }
}
