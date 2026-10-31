/// `HealthProfileReading` sintético (perfil inventado) para pruebas y previsualizaciones. Nunca toca Apple Salud.
struct PreviewHealthProfileReader: HealthProfileReading {
    var profile = HealthProfile(ageYears: 38, biologicalSex: .female, weightKg: 63.5, heightCm: 166)

    func readProfile() async throws -> HealthProfile { profile }
}
