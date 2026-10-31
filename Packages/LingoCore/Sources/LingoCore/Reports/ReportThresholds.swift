/// Mínimos de datos de los reportes (T-27a). Informativos, no médicos.
///
/// Regla general: un valor que no alcanza su mínimo no se reporta (`nil`) o se marca `isReliable == false`,
/// y nunca entra en un agregado. La UI usa estas constantes para explicar los estados vacíos.
public enum ReportThresholds {
    /// Un día cuenta como "con datos" si al menos esta fracción de sus minutos (dentro del período) tiene lectura.
    public static let minimumDayCoverage = 0.5
    /// Un bin de 30 min del perfil horario necesita lecturas de al menos tantos días locales distintos;
    /// con menos, sus percentiles son `nil`.
    public static let minimumDaysPerHourlyBin = 3
    /// Una franja del día necesita lecturas de al menos tantos días distintos para sus frecuencias.
    public static let minimumDaysPerTimeSlot = 3
    /// Una semana es comparable si tiene al menos tantos días con datos (`minimumDayCoverage`).
    public static let minimumDaysPerWeek = 4
    /// Una noche es fiable si al menos esta fracción de su ventana completa tiene lectura.
    public static let minimumNightCoverage = 0.7
    /// El resumen de noches necesita al menos tantas noches fiables.
    public static let minimumNightsForSummary = 3
    /// Un agregado de comidas o ejercicios necesita al menos tantos eventos analizables en el grupo.
    public static let minimumEventsPerGroup = 3
    /// Hueco: separación entre lecturas válidas contiguas (o con los bordes del período) mayor que esto (segundos).
    public static let gapSeconds: Int64 = 600
    /// Episodio bajo: lecturas por debajo del rango durante al menos esto (segundos).
    public static let lowEpisodeSeconds: Int64 = 900
    /// Separación máxima entre lecturas de un mismo episodio bajo (segundos).
    public static let lowEpisodeMaxGapSeconds: Int64 = 300
    /// Distancia máxima a un instante objetivo para tomar "la lectura de ese momento" (segundos).
    public static let pointToleranceSeconds: Int64 = 300
    /// Una comida se marca como solapada si hubo otra en las 3 h anteriores (segundos).
    public static let mealOverlapSeconds: Int64 = MealResponse.horizon
}
