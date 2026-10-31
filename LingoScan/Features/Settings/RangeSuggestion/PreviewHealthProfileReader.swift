import Foundation

/// `HealthProfileReading` sintético (perfil inventado) para pruebas y previsualizaciones. Nunca toca Apple Salud.
struct PreviewHealthProfileReader: HealthProfileReading {
    var profile = HealthProfile(ageYears: 38, biologicalSex: .female, weightKg: 63.5, heightCm: 166)

    /// Perfil inventado del reporte en PDF para el médico (T-34): añade fecha de nacimiento y grupo sanguíneo.
    static let medicalPreview = PreviewHealthProfileReader(profile: HealthProfile(
        ageYears: 38, biologicalSex: .female, weightKg: 63.5, heightCm: 166,
        birthDate: Date(timeIntervalSince1970: 576_000_000), bloodType: .oPositive))

    func readProfile() async throws -> HealthProfile { profile }
}
